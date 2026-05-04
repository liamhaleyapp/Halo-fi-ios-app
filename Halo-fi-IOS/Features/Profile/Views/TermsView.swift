//
//  TermsView.swift
//  Halo-fi-IOS
//
//  Thin wrapper around LegalDocumentView so the sign-up screen and any
//  other entry points show the same remote-fetched Terms of Service as
//  the About screen — single source of truth lives in the backend
//  /legal/terms endpoint.
//

import SwiftUI

struct TermsView: View {
  var body: some View {
    LegalDocumentView(
      title: "Terms of Service",
      sections: AboutView.termsOfServiceSections,
      endpoint: APIEndpoints.Legal.terms
    )
  }
}

#Preview {
  TermsView()
}
