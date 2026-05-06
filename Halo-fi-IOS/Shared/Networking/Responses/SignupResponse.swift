//
//  SignupResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/4/25.
//

import Foundation

struct SignupResponse: Codable {
  let idUser: String
  /// True when the backend still needs the user to verify their phone via
  /// SMS OTP before proceeding. Always true for email/password signups
  /// after the verification flow is enabled. Optional so older deploys
  /// that don't return this field still decode.
  let requiresPhoneVerification: Bool?
  /// Whether the SMS dispatch succeeded server-side. If false, the
  /// verification screen should immediately offer the user a "Resend" tap.
  let smsSent: Bool?

  enum CodingKeys: String, CodingKey {
    case idUser = "id_user"
    case requiresPhoneVerification = "requires_phone_verification"
    case smsSent = "sms_sent"
  }
}
