(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-commitment-locked (err u106))
(define-constant err-spending-limit-exceeded (err u107))

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