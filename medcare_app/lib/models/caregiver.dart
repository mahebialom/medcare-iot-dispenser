/// Mirrors one entry under /dispensers/{id}/caregivers/{uid}, written
/// by FirebaseService.saveCaregiverProfile() at sign-up. Only the
/// fields collected at registration — no phone/role/notify, since
/// nothing in the sign-up flow captures those (a placeholder mock
/// version of this model used to fake them; this one only shows real
/// data).
class Caregiver {
  const Caregiver({
    required this.uid,
    required this.fullName,
    required this.username,
    required this.email,
  });

  final String uid;
  final String fullName;
  final String username;
  final String email;

  factory Caregiver.fromJson(String uid, Map<dynamic, dynamic> j) => Caregiver(
        uid: uid,
        fullName: (j['fullName'] as String?) ?? 'Caregiver',
        username: (j['username'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
      );
}