(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-commitment-locked (err u106))
(define-constant err-spending-limit-exceeded (err u107))

(define-constant err-refill-not-due (err u108))
(define-constant err-recurring-not-found (err u109))
(define-constant err-invalid-interval (err u110))

(define-constant err-emergency-not-found (err u111))
(define-constant err-cooldown-active (err u112))
(define-constant err-emergency-exists (err u113))
(define-constant emergency-cooldown-blocks u144)

(define-constant err-delegation-not-found (err u114))
(define-constant err-delegate-limit-exceeded (err u115))
(define-constant err-delegation-exists (err u116))

(define-map budget-commitments
  { user: principal }
  {
    locked-amount: uint,
    spending-limit: uint,
    spent-amount: uint,
    approver: principal,
    created-at: uint,
    active: bool
  }
)

(define-map pending-approvals
  { user: principal, request-id: uint }
  {
    amount: uint,
    recipient: principal,
    reason: (string-ascii 100),
    requested-at: uint,
    approved: bool
  }
)

(define-map approval-counters
  { user: principal }
  { next-id: uint }
)

(define-public (create-commitment (locked-amount uint) (spending-limit uint) (approver principal))
  (let (
    (user tx-sender)
    (current-balance (stx-get-balance user))
  )
    (asserts! (> locked-amount u0) err-invalid-amount)
    (asserts! (>= current-balance locked-amount) err-insufficient-funds)
    (asserts! (is-none (map-get? budget-commitments {user: user})) err-already-exists)
    
    (try! (stx-transfer? locked-amount user (as-contract tx-sender)))
    
    (map-set budget-commitments
      {user: user}
      {
        locked-amount: locked-amount,
        spending-limit: spending-limit,
        spent-amount: u0,
        approver: approver,
        created-at: stacks-block-height,
        active: true
      }
    )
    
    (map-set approval-counters {user: user} {next-id: u1})
    
    (ok true)
  )
)

(define-public (request-spending (amount uint) (recipient principal) (reason (string-ascii 100)))
  (let (
    (user tx-sender)
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (counter-data (default-to {next-id: u1} (map-get? approval-counters {user: user})))
    (request-id (get next-id counter-data))
  )
    (asserts! (get active commitment) err-commitment-locked)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= (+ (get spent-amount commitment) amount) (get spending-limit commitment)) err-spending-limit-exceeded)
    
    (map-set pending-approvals
      {user: user, request-id: request-id}
      {
        amount: amount,
        recipient: recipient,
        reason: reason,
        requested-at: stacks-block-height,
        approved: false
      }
    )
    
    (map-set approval-counters {user: user} {next-id: (+ request-id u1)})
    
    (ok request-id)
  )
)

(define-public (approve-spending (user principal) (request-id uint))
  (let (
    (approver tx-sender)
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (request (unwrap! (map-get? pending-approvals {user: user, request-id: request-id}) err-not-found))
  )
    (asserts! (is-eq approver (get approver commitment)) err-unauthorized)
    (asserts! (not (get approved request)) err-already-exists)
    
    (map-set pending-approvals
      {user: user, request-id: request-id}
      (merge request {approved: true})
    )
    
    (ok true)
  )
)

(define-public (execute-spending (request-id uint))
  (let (
    (user tx-sender)
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (request (unwrap! (map-get? pending-approvals {user: user, request-id: request-id}) err-not-found))
    (amount (get amount request))
    (recipient (get recipient request))
  )
    (asserts! (get approved request) err-unauthorized)
    (asserts! (get active commitment) err-commitment-locked)
    (asserts! (<= amount (get locked-amount commitment)) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    
    (map-set budget-commitments
      {user: user}
      (merge commitment {
        spent-amount: (+ (get spent-amount commitment) amount),
        locked-amount: (- (get locked-amount commitment) amount)
      })
    )
    
    (map-delete pending-approvals {user: user, request-id: request-id})
    
    (ok true)
  )
)

(define-public (withdraw-remaining)
  (let (
    (user tx-sender)
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (remaining-amount (get locked-amount commitment))
  )
    (asserts! (get active commitment) err-commitment-locked)
    (asserts! (> remaining-amount u0) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? remaining-amount tx-sender user)))
    
    (map-set budget-commitments
      {user: user}
      (merge commitment {
        locked-amount: u0,
        active: false
      })
    )
    
    (ok remaining-amount)
  )
)

(define-public (deactivate-commitment)
  (let (
    (user tx-sender)
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
  )
    (map-set budget-commitments
      {user: user}
      (merge commitment {active: false})
    )
    
    (ok true)
  )
)

(define-read-only (get-commitment (user principal))
  (map-get? budget-commitments {user: user})
)

(define-read-only (get-pending-request (user principal) (request-id uint))
  (map-get? pending-approvals {user: user, request-id: request-id})
)

(define-read-only (get-next-request-id (user principal))
  (get next-id (default-to {next-id: u1} (map-get? approval-counters {user: user})))
)

(define-map spending-history
  { user: principal, transaction-id: uint }
  {
    amount: uint,
    recipient: principal,
    reason: (string-ascii 100),
    category: (string-ascii 20),
    executed-at: uint,
    block-height: uint
  }
)

(define-map transaction-counters
  { user: principal }
  { total-transactions: uint }
)

(define-public (set-expense-category (request-id uint) (category (string-ascii 20)))
  (let (
    (user tx-sender)
    (request (unwrap! (map-get? pending-approvals {user: user, request-id: request-id}) err-not-found))
  )
    (asserts! (not (get approved request)) err-unauthorized)
    (ok true)
  )
)

(define-private (record-spending-history (user principal) (amount uint) (recipient principal) (reason (string-ascii 100)))
  (let (
    (counter (default-to {total-transactions: u0} (map-get? transaction-counters {user: user})))
    (transaction-id (+ (get total-transactions counter) u1))
    (category (extract-category reason))
  )
    (map-set spending-history
      {user: user, transaction-id: transaction-id}
      {
        amount: amount,
        recipient: recipient,
        reason: reason,
        category: category,
        executed-at: stacks-block-height,
        block-height: stacks-block-height
      }
    )
    (map-set transaction-counters {user: user} {total-transactions: transaction-id})
    (ok transaction-id)
  )
)

(define-private (extract-category (reason (string-ascii 100)))
  "general"
)

(define-read-only (get-spending-history (user principal) (transaction-id uint))
  (map-get? spending-history {user: user, transaction-id: transaction-id})
)

(define-read-only (get-total-transactions (user principal))
  (get total-transactions (default-to {total-transactions: u0} (map-get? transaction-counters {user: user})))
)

(define-read-only (calculate-spending-rate (user principal))
  (let (
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (blocks-elapsed (- stacks-block-height (get created-at commitment)))
    (spent-amount (get spent-amount commitment))
  )
    (if (> blocks-elapsed u0)
      (ok (/ spent-amount blocks-elapsed))
      (ok u0)
    )
  )
)


(define-map recurring-commitments
  { user: principal }
  {
    refill-amount: uint,
    refill-limit: uint,
    interval-blocks: uint,
    last-refill-block: uint,
    auto-refill-enabled: bool,
    max-refills: uint,
    refills-completed: uint
  }
)

(define-public (setup-recurring-commitment 
  (refill-amount uint) 
  (refill-limit uint) 
  (interval-blocks uint) 
  (max-refills uint))
  (let (
    (user tx-sender)
    (existing-commitment (map-get? budget-commitments {user: user}))
  )
    (asserts! (> refill-amount u0) err-invalid-amount)
    (asserts! (> interval-blocks u0) err-invalid-interval)
    (asserts! (> max-refills u0) err-invalid-amount)
    (asserts! (is-some existing-commitment) err-not-found)
    
    (map-set recurring-commitments
      {user: user}
      {
        refill-amount: refill-amount,
        refill-limit: refill-limit,
        interval-blocks: interval-blocks,
        last-refill-block: stacks-block-height,
        auto-refill-enabled: true,
        max-refills: max-refills,
        refills-completed: u0
      }
    )
    
    (ok true)
  )
)

(define-public (execute-refill)
  (let (
    (user tx-sender)
    (recurring (unwrap! (map-get? recurring-commitments {user: user}) err-recurring-not-found))
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (blocks-passed (- stacks-block-height (get last-refill-block recurring)))
    (refill-amount (get refill-amount recurring))
  )
    (asserts! (get auto-refill-enabled recurring) err-commitment-locked)
    (asserts! (>= blocks-passed (get interval-blocks recurring)) err-refill-not-due)
    (asserts! (< (get refills-completed recurring) (get max-refills recurring)) err-spending-limit-exceeded)
    (asserts! (>= (stx-get-balance user) refill-amount) err-insufficient-funds)
    
    (try! (stx-transfer? refill-amount user (as-contract tx-sender)))
    
    (map-set budget-commitments
      {user: user}
      (merge commitment {
        locked-amount: (+ (get locked-amount commitment) refill-amount),
        spending-limit: (get refill-limit recurring)
      })
    )
    
    (map-set recurring-commitments
      {user: user}
      (merge recurring {
        last-refill-block: stacks-block-height,
        refills-completed: (+ (get refills-completed recurring) u1)
      })
    )
    
    (ok refill-amount)
  )
)

(define-public (toggle-auto-refill)
  (let (
    (user tx-sender)
    (recurring (unwrap! (map-get? recurring-commitments {user: user}) err-recurring-not-found))
  )
    (map-set recurring-commitments
      {user: user}
      (merge recurring {auto-refill-enabled: (not (get auto-refill-enabled recurring))})
    )
    
    (ok (not (get auto-refill-enabled recurring)))
  )
)

(define-read-only (get-recurring-commitment (user principal))
  (map-get? recurring-commitments {user: user})
)

(define-read-only (is-refill-due (user principal))
  (match (map-get? recurring-commitments {user: user})
    recurring (let (
      (blocks-passed (- stacks-block-height (get last-refill-block recurring)))
    )
      (>= blocks-passed (get interval-blocks recurring))
    )
    false
  )
)

(define-map emergency-withdrawals
  { user: principal }
  {
    amount: uint,
    initiated-at: uint,
    reason: (string-ascii 100),
    completed: bool
  }
)

(define-public (initiate-emergency-withdrawal (reason (string-ascii 100)))
  (let (
    (user tx-sender)
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (locked-amt (get locked-amount commitment))
  )
    (asserts! (> locked-amt u0) err-insufficient-funds)
    (asserts! (is-none (map-get? emergency-withdrawals {user: user})) err-emergency-exists)
    
    (map-set emergency-withdrawals
      {user: user}
      {
        amount: locked-amt,
        initiated-at: stacks-block-height,
        reason: reason,
        completed: false
      }
    )
    
    (ok locked-amt)
  )
)

(define-public (complete-emergency-withdrawal)
  (let (
    (user tx-sender)
    (emergency (unwrap! (map-get? emergency-withdrawals {user: user}) err-emergency-not-found))
    (commitment (unwrap! (map-get? budget-commitments {user: user}) err-not-found))
    (blocks-passed (- stacks-block-height (get initiated-at emergency)))
    (withdrawal-amount (get amount emergency))
  )
    (asserts! (not (get completed emergency)) err-already-exists)
    (asserts! (>= blocks-passed emergency-cooldown-blocks) err-cooldown-active)
    (asserts! (> withdrawal-amount u0) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender user)))
    
    (map-set budget-commitments
      {user: user}
      (merge commitment {locked-amount: u0, active: false})
    )
    
    (map-set emergency-withdrawals
      {user: user}
      (merge emergency {completed: true})
    )
    
    (ok withdrawal-amount)
  )
)

(define-public (cancel-emergency-withdrawal)
  (let (
    (user tx-sender)
    (emergency (unwrap! (map-get? emergency-withdrawals {user: user}) err-emergency-not-found))
  )
    (asserts! (not (get completed emergency)) err-already-exists)
    (map-delete emergency-withdrawals {user: user})
    (ok true)
  )
)

(define-read-only (get-emergency-withdrawal (user principal))
  (map-get? emergency-withdrawals {user: user})
)

(define-read-only (emergency-cooldown-complete (user principal))
  (match (map-get? emergency-withdrawals {user: user})
    emergency (>= (- stacks-block-height (get initiated-at emergency)) emergency-cooldown-blocks)
    false
  )
)

(define-map budget-delegations
  { delegator: principal, delegate-id: uint }
  {
    delegate: principal,
    allocated-amount: uint,
    spent-amount: uint,
    created-at: uint,
    active: bool
  }
)

(define-map delegation-counters
  { delegator: principal }
  { next-delegate-id: uint }
)

(define-public (delegate-budget (delegate principal) (allocated-amount uint))
  (let (
    (delegator tx-sender)
    (commitment (unwrap! (map-get? budget-commitments {user: delegator}) err-not-found))
    (counter-data (default-to {next-delegate-id: u1} (map-get? delegation-counters {delegator: delegator})))
    (delegate-id (get next-delegate-id counter-data))
    (available-amount (- (get locked-amount commitment) (get spent-amount commitment)))
  )
    (asserts! (get active commitment) err-commitment-locked)
    (asserts! (> allocated-amount u0) err-invalid-amount)
    (asserts! (<= allocated-amount available-amount) err-insufficient-funds)
    
    (map-set budget-delegations
      {delegator: delegator, delegate-id: delegate-id}
      {
        delegate: delegate,
        allocated-amount: allocated-amount,
        spent-amount: u0,
        created-at: stacks-block-height,
        active: true
      }
    )
    
    (map-set delegation-counters {delegator: delegator} {next-delegate-id: (+ delegate-id u1)})
    (ok delegate-id)
  )
)

(define-public (spend-as-delegate (delegator principal) (delegate-id uint) (amount uint) (recipient principal))
  (let (
    (delegate tx-sender)
    (delegation (unwrap! (map-get? budget-delegations {delegator: delegator, delegate-id: delegate-id}) err-delegation-not-found))
    (commitment (unwrap! (map-get? budget-commitments {user: delegator}) err-not-found))
  )
    (asserts! (is-eq delegate (get delegate delegation)) err-unauthorized)
    (asserts! (get active delegation) err-commitment-locked)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= (+ (get spent-amount delegation) amount) (get allocated-amount delegation)) err-delegate-limit-exceeded)
    (asserts! (<= amount (get locked-amount commitment)) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    
    (map-set budget-delegations
      {delegator: delegator, delegate-id: delegate-id}
      (merge delegation {spent-amount: (+ (get spent-amount delegation) amount)})
    )
    
    (map-set budget-commitments
      {user: delegator}
      (merge commitment {
        spent-amount: (+ (get spent-amount commitment) amount),
        locked-amount: (- (get locked-amount commitment) amount)
      })
    )
    (ok true)
  )
)

(define-public (revoke-delegation (delegate-id uint))
  (let (
    (delegator tx-sender)
    (delegation (unwrap! (map-get? budget-delegations {delegator: delegator, delegate-id: delegate-id}) err-delegation-not-found))
  )
    (map-set budget-delegations
      {delegator: delegator, delegate-id: delegate-id}
      (merge delegation {active: false})
    )
    (ok true)
  )
)

(define-read-only (get-delegation (delegator principal) (delegate-id uint))
  (map-get? budget-delegations {delegator: delegator, delegate-id: delegate-id})
)