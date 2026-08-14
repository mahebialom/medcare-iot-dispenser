const { setGlobalOptions } = require("firebase-functions/v2");
setGlobalOptions({ region: 'asia-southeast1' });

const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { getMessaging } = require("firebase-admin/messaging");
const { onValueCreated } = require("firebase-functions/v2/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");

initializeApp();

// Must match kDeviceId in the Flutter app (lib/config.dart) and
// DEVICE_ID in the ESP32 firmware.
const DEVICE_ID = "dispenser_01";

// ── Helpers ──────────────────────────────────────────────────────────

async function getTokens() {
  const db = getDatabase();
  const snap = await db.ref(`dispensers/${DEVICE_ID}/fcmTokens`).get();
  if (!snap.exists()) return [];
  return Object.keys(snap.val());
}

async function sendToAll({ id, type, title, body }) {
  const tokens = await getTokens();
  if (tokens.length === 0) {
    logger.info("No registered FCM tokens — nothing to send.");
    return;
  }

  const message = {
    tokens,
    // DATA-ONLY payload (no "notification" key) — deliberate. The
    // Flutter side displays the notification itself: foreground via
    // NotificationService, background/killed via the top-level
    // firebaseMessagingBackgroundHandler. Both use this same `id` for
    // de-dup against the client's own event-stream path, so the same
    // event never shows twice no matter which path catches it first.
    data: { id, type, title, body },
    android: { priority: "high" },
  };

  const response = await getMessaging().sendEachForMulticast(message);
  logger.info(`Sent "${id}" to ${response.successCount}/${tokens.length} token(s).`);

  // Prune tokens that are no longer valid (app uninstalled, etc.).
  const staleTokens = [];
  response.responses.forEach((r, i) => {
    if (!r.success && r.error?.code === "messaging/registration-token-not-registered") {
      staleTokens.push(tokens[i]);
    }
  });
  if (staleTokens.length > 0) {
    const updates = {};
    staleTokens.forEach((t) => (updates[`dispensers/${DEVICE_ID}/fcmTokens/${t}`] = null));
    await getDatabase().ref().update(updates);
    logger.info(`Removed ${staleTokens.length} stale token(s).`);
  }
}

//Medicine Missed / Stock Low / Stock Critical
// Fires the instant the firmware writes a matching event to /events.
// Other event types the firmware also logs (medicine_taken,
// medicine_not_taken nags, refill_mode) are intentionally NOT pushed 
// same filtering the in-app History tab already applies.

exports.onDeviceEvent = onValueCreated(`dispensers/${DEVICE_ID}/events/{eventId}`, async (event) => {
  const data = event.data.val();
  const eventId = event.params.eventId;
  if (!data || !data.type) return;

  const map = {
    medicine_missed: {
      type: "missed",
      title: "Medicine Missed",
      body: `${data.name} was not taken in time.`,
    },
    stock_low: {
      type: "stockLow",
      title: "Stock Running Low",
      body: `${data.name} is running low — consider a refill soon.`,
    },
    stock_critical: {
      type: "stockCritical",
      title: "Stock Critical",
      body: `${data.name} is critically low — refill needed now.`,
    },
  };

  const notif = map[data.type];
  if (!notif) return;

  await sendToAll({ id: `event_${eventId}`, ...notif });
});

//"Due within 20 minutes" reminder
// a schedule and computes it, mirroring AppState._checkUpcomingReminders()
// Runs every 5 minutes. A per-day "already notified" marker prevents
// re-sending the same reminder repeatedly across that 5-minute polling
// window while a dose sits in its final 20 minutes.

function boundaryMinuteOfDay(period, hour, minute) {
  switch (period) {
    case 0: return 11 * 60 + 59; // Morning
    case 1: return 15 * 60 + 59; // Lunch
    case 2: return 22 * 60 + 59; // Night
    case 3: return hour * 60 + minute; // Exact
    default: return null;
  }
}

exports.checkUpcomingReminders = onSchedule(
  { schedule: "every 5 minutes", timeZone: "Asia/Dhaka" },
  async () => {
    const db = getDatabase();
    const slotsSnap = await db.ref(`dispensers/${DEVICE_ID}/slots`).get();
    if (!slotsSnap.exists()) return;

    const slotsRaw = slotsSnap.val();
    // Same array-vs-map quirk the Flutter client has to handle for
    // dense-integer-keyed nodes like /slots — see FirebaseService.watchSlots().
    const slots = Array.isArray(slotsRaw) ? slotsRaw : Object.keys(slotsRaw).map((k) => slotsRaw[k]);

    const now = new Date();
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const today = `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`;

    for (let slotIndex = 0; slotIndex < slots.length; slotIndex++) {
      const slot = slots[slotIndex];
      if (!slot || !slot.enabled || !Array.isArray(slot.schedules)) continue;

      for (let i = 0; i < slot.schedules.length; i++) {
        const s = slot.schedules[i];
        if (!s || s.takenToday) continue;
        const boundary = boundaryMinuteOfDay(s.period, s.hour, s.minute);
        if (boundary === null) continue;
        const minutesLeft = boundary - nowMinutes;
        if (minutesLeft < 0 || minutesLeft > 20) continue;

        const markerPath = `dispensers/${DEVICE_ID}/notifiedReminders/${today}/${slotIndex}_${i}`;
        const already = await db.ref(markerPath).get();
        if (already.exists()) continue;

        await sendToAll({
          id: `reminder_${slotIndex}_${i}_${today}`,
          type: "upcomingReminder",
          title: "Dose Due Soon",
          body: `${slot.medicineName} is due within 20 minutes.`,
        });
        await db.ref(markerPath).set(true);
      }
    }
  }
);
