class AppTokenModel {
  final String token;
  final int expires;
  final String userId;
  final String domainId;

  AppTokenModel({
    required this.token,
    required this.expires,
    required this.userId,
    required this.domainId,
  });

  factory AppTokenModel.fromJson(Map<String, dynamic> json) {
    return AppTokenModel(
      token: json['Token'] ?? '',
      expires: json['Expires'] ?? 0,
      userId: json['UserID'] ?? '',
      domainId: json['DomainID'] ?? '',
    );
  }
}