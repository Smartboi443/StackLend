;; StackLend - Independent P2P Lending Protocol
;; A decentralized lending platform on Stacks blockchain for STX lending

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-LOAN-NOT-FOUND (err u102))
(define-constant ERR-LOAN-ALREADY-ACTIVE (err u103))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u104))
(define-constant ERR-LOAN-NOT-DUE (err u105))
(define-constant ERR-LOAN-DEFAULTED (err u106))
(define-constant ERR-INVALID-PRINCIPAL (err u107))
(define-constant ERR-PAYMENT-TOO-SMALL (err u108))
(define-constant ERR-NO-LIQUIDATION-NEEDED (err u109))

;; Constants
(define-constant BLOCKS-PER-DAY u144) ;; Approximate number of blocks per day
(define-constant PENALTY-RATE u10) ;; 10% penalty rate for late payments
(define-constant LIQUIDATION-THRESHOLD u130) ;; 130% minimum collateral ratio before liquidation

;; Status constants
(define-constant STATUS-PENDING "PENDING")
(define-constant STATUS-ACTIVE "ACTIVE")
(define-constant STATUS-REPAID "REPAID")
(define-constant STATUS-LIQUIDATED "LIQUIDATED")
(define-constant STATUS-DEFAULTED "DEFAULTED")

;; Data variables
(define-data-var minimum-collateral-ratio uint u150) ;; 150% collateralization ratio
(define-data-var contract-owner principal tx-sender)

;; Loan data structure
(define-map loans
    {loan-id: uint}
    {
        borrower: principal,
        lender: (optional principal),
        amount: uint,
        collateral: uint,
        interest-rate: uint,
        duration: uint,
        start-height: uint,
        last-payment-height: uint,
        payment-interval: uint,
        payment-amount: uint,
        remaining-amount: uint,
        status: (string-ascii 20)
    }
)

;; Payment schedule tracking
(define-map payment-schedules
    {loan-id: uint}
    {
        next-payment-height: uint,
        missed-payments: uint,
        total-penalties: uint
    }
)

;; Contract state variables
(define-data-var next-loan-id uint u1)
(define-data-var total-stx-locked uint u0)

;; Read-only functions
(define-read-only (get-loan (loan-id uint))
    (map-get? loans {loan-id: loan-id})
)

(define-read-only (get-payment-schedule (loan-id uint))
    (map-get? payment-schedules {loan-id: loan-id})
)

(define-read-only (get-collateral-ratio (collateral uint) (loan-amount uint))
    (let
        (
            (ratio (* (/ collateral loan-amount) u100))
        )
        ratio
    )
)

(define-read-only (get-current-collateral-ratio (loan-id uint))
    (let
        (
            (loan (unwrap! (get-loan loan-id) u0))
            (ratio (get-collateral-ratio (get collateral loan) (get remaining-amount loan)))
        )
        ratio
    )
)

(define-read-only (check-liquidation-needed (loan-id uint))
    (let
        (
            (current-ratio (get-current-collateral-ratio loan-id))
        )
        (< current-ratio LIQUIDATION-THRESHOLD)
    )
)

;; Private functions
(define-private (calculate-penalty (payment-amount uint))
    (/ (* payment-amount PENALTY-RATE) u100)
)

(define-private (update-payment-schedule (loan-id uint) (start-height uint) (payment-interval uint))
    (begin
        (map-set payment-schedules
            {loan-id: loan-id}
            {
                next-payment-height: (+ start-height payment-interval),
                missed-payments: u0,
                total-penalties: u0
            }
        )
        true
    )
)

;; Public functions
(define-public (create-loan (amount uint) (collateral uint) (interest-rate uint) (duration uint) (payment-interval uint))
    (let
        (
            (loan-id (var-get next-loan-id))
            (collateral-ratio (get-collateral-ratio collateral amount))
            (payment-amount (/ (+ amount (* amount interest-rate)) duration))
        )
        (asserts! (>= collateral-ratio (var-get minimum-collateral-ratio)) ERR-INSUFFICIENT-COLLATERAL)
        (asserts! (> amount u0) ERR-INVALID-PRINCIPAL)
        (try! (stx-transfer? collateral tx-sender (as-contract tx-sender)))
        
        (var-set total-stx-locked (+ (var-get total-stx-locked) collateral))
        
        (map-set loans
            {loan-id: loan-id}
            {
                borrower: tx-sender,
                lender: none,
                amount: amount,
                collateral: collateral,
                interest-rate: interest-rate,
                duration: duration,
                start-height: u0,
                last-payment-height: u0,
                payment-interval: payment-interval,
                payment-amount: payment-amount,
                remaining-amount: amount,
                status: STATUS-PENDING
            }
        )
        (var-set next-loan-id (+ loan-id u1))
        (ok loan-id)
    )
)

(define-public (fund-loan (loan-id uint))
    (let
        (
            (loan (unwrap! (get-loan loan-id) ERR-LOAN-NOT-FOUND))
            (amount (get amount loan))
        )
        (asserts! (is-eq (get status loan) STATUS-PENDING) ERR-LOAN-ALREADY-ACTIVE)
        (try! (stx-transfer? amount tx-sender (get borrower loan)))
        
        (map-set loans
            {loan-id: loan-id}
            (merge loan {
                lender: (some tx-sender),
                start-height: block-height,
                last-payment-height: block-height,
                status: STATUS-ACTIVE
            })
        )
        
        (asserts! (update-payment-schedule loan-id block-height (get payment-interval loan)) ERR-LOAN-NOT-FOUND)
        
        (ok true)
    )
)

(define-public (make-payment (loan-id uint))
    (let
        (
            (loan (unwrap! (get-loan loan-id) ERR-LOAN-NOT-FOUND))
            (schedule (unwrap! (get-payment-schedule loan-id) ERR-LOAN-NOT-FOUND))
            (payment-amount (get payment-amount loan))
            (lender (unwrap! (get lender loan) ERR-LOAN-NOT-FOUND))
            (penalty (if (>= block-height (get next-payment-height schedule))
                        (calculate-penalty payment-amount)
                        u0))
            (total-payment (+ payment-amount penalty))
        )
        (asserts! (is-eq (get status loan) STATUS-ACTIVE) ERR-LOAN-NOT-FOUND)
        (asserts! (is-eq (get borrower loan) tx-sender) ERR-NOT-AUTHORIZED)
        
        (try! (stx-transfer? total-payment tx-sender lender))
        
        (map-set loans
            {loan-id: loan-id}
            (merge loan {
                last-payment-height: block-height,
                remaining-amount: (- (get remaining-amount loan) payment-amount)
            })
        )
        
        (map-set payment-schedules
            {loan-id: loan-id}
            (merge schedule {
                next-payment-height: (+ block-height (get payment-interval loan)),
                total-penalties: (+ (get total-penalties schedule) penalty)
            })
        )
        
        (ok true)
    )
)

(define-public (check-and-liquidate (loan-id uint))
    (let
        (
            (loan (unwrap! (get-loan loan-id) ERR-LOAN-NOT-FOUND))
            (schedule (unwrap! (get-payment-schedule loan-id) ERR-LOAN-NOT-FOUND))
            (lender (unwrap! (get lender loan) ERR-LOAN-NOT-FOUND))
            (needs-liquidation (check-liquidation-needed loan-id))
        )
        (asserts! needs-liquidation ERR-NO-LIQUIDATION-NEEDED)
        
        (as-contract
            (try! (stx-transfer? (get collateral loan) lender tx-sender))
        )
        
        (var-set total-stx-locked (- (var-get total-stx-locked) (get collateral loan)))
        
        (map-set loans
            {loan-id: loan-id}
            (merge loan {
                status: STATUS-LIQUIDATED
            })
        )
        
        (ok true)
    )
)

;; Admin functions
(define-public (set-minimum-collateral-ratio (new-ratio uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set minimum-collateral-ratio new-ratio)
        (ok true)
    )
)

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)