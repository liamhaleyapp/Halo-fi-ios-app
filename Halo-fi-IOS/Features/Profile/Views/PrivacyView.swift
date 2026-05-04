//
//  PrivacyView.swift
//  Halo-fi-IOS
//
//  Thin wrapper around LegalDocumentView so the sign-up screen and any
//  other entry points show the same remote-fetched Privacy Policy as
//  the About screen — single source of truth lives in the backend
//  /legal/privacy endpoint.
//

import SwiftUI

struct PrivacyView: View {
  var body: some View {
    LegalDocumentView(
      title: "Privacy Policy",
      sections: AboutView.privacyPolicySections,
      endpoint: APIEndpoints.Legal.privacy
    )
  }
}

#Preview {
  PrivacyView()
}
