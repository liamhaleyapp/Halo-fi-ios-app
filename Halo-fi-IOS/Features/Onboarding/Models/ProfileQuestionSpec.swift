//
//  ProfileQuestionSpec.swift
//  Halo-fi-IOS
//
//  Data-driven benefits-profile question tree (Sep-2026 onboarding).
//
//  The question list is PENDING final sign-off from Liam + Andrew, so the
//  tree is an ordered array of specs with a `showIf` predicate: re-ordering,
//  re-wording, or adding a branch is a change to `ProfileQuestions.v1`, not
//  to the view. Every question is skippable; every answer is one tap and
//  is PATCHed to /users/me immediately (idempotent).
//
//  Copy rules (Andrew, 2026-09-03): never "you will lose benefits"; every
//  computed number says "Estimate"; explainers point to a free human
//  counselor (WIPA) when it matters.
//

import Foundation

struct ProfileExplainer: Equatable {
    let title: String
    let lines: [String]
    /// Optional external link (e.g. the WIPA finder).
    let linkTitle: String?
    let linkURL: URL?

    init(title: String, lines: [String], linkTitle: String? = nil, linkURL: URL? = nil) {
        self.title = title
        self.lines = lines
        self.linkTitle = linkTitle
        self.linkURL = linkURL
    }

    static let wipaURL = URL(string: "https://choosework.ssa.gov/findhelp")!

    static let bpqyWalkthrough = ProfileExplainer(
        title: "How to check your record",
        lines: [
            "Social Security keeps its own record of whether you are statutorily blind. It is on your award letter, or on a Benefits Planning Query, called a BPQY.",
            "To get a BPQY, call Social Security at 1-800-772-1213, or visit your local field office and ask for a Benefits Planning Query.",
            "Until it is confirmed, Blind Work Expense features stay locked. You can still log work expenses as Impairment-Related Work Expenses.",
        ],
        linkTitle: "Find a free benefits counselor",
        linkURL: wipaURL
    )

    static let deemingReferral = ProfileExplainer(
        title: "This is one for a human counselor",
        lines: [
            "When a spouse or a parent shares your household, Social Security may count some of their income and resources as yours. That is called deeming.",
            "HaloFi does not do deeming math. A free benefits counselor can walk through your exact situation.",
        ],
        linkTitle: "Talk to a free benefits counselor",
        linkURL: wipaURL
    )

    static let ssaPaymentHelp = ProfileExplainer(
        title: "Not sure? Here is how to tell",
        lines: [
            "SSI pays on the 1st of the month and the most it pays is 994 dollars. SSDI pays on a Wednesday and can be any amount.",
            "After you link your bank, HaloFi can look for Treasury deposits and help you figure out which one you receive.",
        ]
    )

    static let ableExplainer = ProfileExplainer(
        title: "What is an ABLE account?",
        lines: [
            "An ABLE account is a savings account for people whose disability began before age 46.",
            "Money in it, up to 100,000 dollars, is not counted toward the SSI resource limit. That is why HaloFi asks.",
        ]
    )
}

struct ProfileOption: Identifiable, Equatable {
    let id: String
    let title: String
    /// The partial update to persist when this option is chosen. Empty for
    /// "I'm not sure" answers that only show an explainer.
    let patch: BenefitsProfilePatch
    /// Shown as a sheet before continuing.
    let explainer: ProfileExplainer?

    init(_ id: String, _ title: String, patch: BenefitsProfilePatch = .none, explainer: ProfileExplainer? = nil) {
        self.id = id
        self.title = title
        self.patch = patch
        self.explainer = explainer
    }
}

struct ProfileQuestionSpec: Identifiable {
    let id: String
    /// Backend field this question answers (for Settings to show the
    /// current value).
    let field: String
    /// The heading AND the accessibility label (GOV.UK pattern).
    let question: String
    let helpText: String?
    let options: [ProfileOption]
    /// Label of the always-present escape hatch; nil hides it (promise
    /// screen only).
    let skipTitle: String?
    /// Predicate over answers-so-far keyed by question id → option id.
    let showIf: ([String: String]) -> Bool

    init(
        id: String,
        field: String,
        question: String,
        helpText: String? = nil,
        options: [ProfileOption],
        skipTitle: String? = "Skip for now",
        showIf: @escaping ([String: String]) -> Bool = { _ in true }
    ) {
        self.id = id
        self.field = field
        self.question = question
        self.helpText = helpText
        self.options = options
        self.skipTitle = skipTitle
        self.showIf = showIf
    }

    /// Settings-facing short title (row label).
    var shortTitle: String {
        switch field {
        case "gets_ssa_payment": return "Social Security payment"
        case "benefit_type": return "Which benefit"
        case "household_size": return "Household size"
        case "household_type": return "Who shares your household"
        case "ssi_eligible_couple": return "Spouse on SSI"
        case "blind_status": return "Statutorily blind"
        case "work_status": return "Work status"
        case "has_able_account": return "ABLE account"
        case "promise_accepted_at": return "Our promise"
        default: return question
        }
    }
}

enum ProfileQuestions {
    private static func householdSizeOptions() -> [ProfileOption] {
        [
            ProfileOption("1", "1 — just me", patch: BenefitsProfilePatch(householdSize: 1)),
            ProfileOption("2", "2", patch: BenefitsProfilePatch(householdSize: 2)),
            ProfileOption("3", "3", patch: BenefitsProfilePatch(householdSize: 3)),
            ProfileOption("4", "4 or more", patch: BenefitsProfilePatch(householdSize: 4)),
        ]
    }

    /// Andrew's wording, 2026-09-03. Q6 (Trial Work Period) deferred to V2;
    /// Q8 (state) lives in Settings → Benefits profile.
    static let v1: [ProfileQuestionSpec] = [
        ProfileQuestionSpec(
            id: "ssa_payment",
            field: "gets_ssa_payment",
            question: "Do you receive a monthly payment from Social Security?",
            options: [
                ProfileOption("yes", "Yes", patch: BenefitsProfilePatch(getsSsaPayment: "yes")),
                ProfileOption("no", "No", patch: BenefitsProfilePatch(getsSsaPayment: "no")),
                ProfileOption("unsure", "I'm not sure", patch: BenefitsProfilePatch(getsSsaPayment: "unsure"), explainer: .ssaPaymentHelp),
            ],
            skipTitle: "Skip for now"
        ),
        ProfileQuestionSpec(
            id: "benefit_type",
            field: "benefit_type",
            question: "Which of these do you receive?",
            options: [
                ProfileOption("ssi", "SSI — Supplemental Security Income", patch: BenefitsProfilePatch(benefitType: "ssi")),
                ProfileOption("ssdi", "SSDI — Social Security Disability Insurance", patch: BenefitsProfilePatch(benefitType: "ssdi")),
                ProfileOption("both", "Both", patch: BenefitsProfilePatch(benefitType: "both")),
                ProfileOption("other", "Something else", patch: BenefitsProfilePatch(benefitType: "other")),
                ProfileOption("unsure", "Help me figure it out", patch: BenefitsProfilePatch(benefitType: "unsure"), explainer: .bpqyWalkthrough),
            ],
            skipTitle: "Skip for now",
            showIf: { answers in ["yes", "unsure"].contains(answers["ssa_payment"] ?? "") }
        ),
        ProfileQuestionSpec(
            id: "household_size_no_benefits",
            field: "household_size",
            question: "How many people live in your household, including you?",
            options: householdSizeOptions(),
            showIf: { answers in answers["ssa_payment"] == "no" }
        ),
        ProfileQuestionSpec(
            id: "household_type",
            field: "household_type",
            question: "Does anyone share your household or SSI record — a spouse, or parents if you're under 18?",
            options: [
                ProfileOption("alone", "Just me", patch: BenefitsProfilePatch(householdType: "alone")),
                ProfileOption("spouse", "Married", patch: BenefitsProfilePatch(householdType: "spouse"), explainer: .deemingReferral),
                ProfileOption("parents_under_18", "Under 18, living with parents", patch: BenefitsProfilePatch(householdType: "parents_under_18"), explainer: .deemingReferral),
            ],
            skipTitle: "Skip for now",
            showIf: { answers in ["ssi", "both"].contains(answers["benefit_type"] ?? "") }
        ),
        ProfileQuestionSpec(
            id: "spouse_ssi",
            field: "ssi_eligible_couple",
            question: "Does your spouse also receive SSI?",
            helpText: "If you both receive SSI, Social Security uses the couple limits: 3,000 dollars in resources and 1,491 dollars a month.",
            options: [
                ProfileOption("yes", "Yes", patch: BenefitsProfilePatch(ssiEligibleCouple: true)),
                ProfileOption("no", "No", patch: BenefitsProfilePatch(ssiEligibleCouple: false)),
            ],
            skipTitle: "I'm not sure",
            showIf: { answers in answers["household_type"] == "spouse" }
        ),
        ProfileQuestionSpec(
            id: "household_size_other",
            field: "household_size",
            question: "How many people live in your household, including you?",
            options: householdSizeOptions(),
            showIf: { answers in ["ssdi", "other", "unsure"].contains(answers["benefit_type"] ?? "") }
        ),
        ProfileQuestionSpec(
            id: "blind_status",
            field: "blind_status",
            question: "Does Social Security's own record list you as statutorily blind?",
            helpText: "This is on your award letter or BPQY — not the same as being legally blind in daily life.",
            options: [
                ProfileOption("yes", "Yes", patch: BenefitsProfilePatch(blindStatus: "yes")),
                ProfileOption("no", "No", patch: BenefitsProfilePatch(blindStatus: "no")),
                ProfileOption("unverified", "I'm not sure — help me check", patch: BenefitsProfilePatch(blindStatus: "unverified"), explainer: .bpqyWalkthrough),
            ],
            skipTitle: "Skip for now"
        ),
        ProfileQuestionSpec(
            id: "work_status",
            field: "work_status",
            question: "Are you working now, or planning to start soon?",
            options: [
                ProfileOption("working", "Working now", patch: BenefitsProfilePatch(workStatus: "working")),
                ProfileOption("starting_soon", "Starting soon", patch: BenefitsProfilePatch(workStatus: "starting_soon")),
                ProfileOption("not_now", "Not right now", patch: BenefitsProfilePatch(workStatus: "not_now")),
            ],
            skipTitle: "Skip for now"
        ),
        ProfileQuestionSpec(
            id: "able",
            field: "has_able_account",
            question: "Do you have an ABLE account?",
            options: [
                ProfileOption("yes", "Yes", patch: BenefitsProfilePatch(hasAbleAccount: true)),
                ProfileOption("no", "No", patch: BenefitsProfilePatch(hasAbleAccount: false)),
                ProfileOption("what", "What's that?", explainer: .ableExplainer),
            ],
            skipTitle: "Skip for now"
        ),
        ProfileQuestionSpec(
            id: "promise",
            field: "promise_accepted_at",
            question: "Our promise",
            helpText: "HaloFi gives estimates and education, not decisions. Social Security makes every actual decision about your benefits. We'll always show our math, and we'll always point you to a free human expert when it matters.",
            options: [
                ProfileOption("accepted", "That works for me", patch: BenefitsProfilePatch(promiseAcceptedAt: Date())),
            ],
            skipTitle: nil
        ),
    ]

    /// Onboarding asks only what decides the lane (2026-09-06): the payment,
    /// which benefit, statutory blindness, and the promise. Household, work
    /// status and ABLE come later as a "Finish your benefits profile" card.
    static var onboarding: [ProfileQuestionSpec] {
        v1.filter { ["ssa_payment", "benefit_type", "blind_status", "promise"].contains($0.id) }
    }

    /// The subset of `v1` that Settings → Benefits profile lists (the
    /// promise is shown once at onboarding; a duplicate household-size
    /// question is collapsed to one row).
    static var settingsRows: [ProfileQuestionSpec] {
        var seenFields = Set<String>()
        return v1.filter { spec in
            guard spec.field != "promise_accepted_at" else { return false }
            return seenFields.insert(spec.field).inserted
        }
    }
}
