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
(define-constant ERR-INVALID-INTEREST-RATE (err u108))
(define-constant ERR-INVALID-DURATION (err u109))
(define-constant ERR-INVALID-RATIO (err u110))

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
        status: (string-ascii 20)
    }
)

;; User balances for STX
(define-map user-balances principal uint)

;; Contract state variables
(define-data-var next-loan-id uint u1)
(define-data-var total-stx-locked uint u0)

;; Constants for validation
(define-constant MAX-INTEREST-RATE u1000) ;; 10% max interest rate
(define-constant MAX-LOAN-DURATION u52560) ;; Max 1 year (approx. block height)
(define-constant MIN-COLLATERAL-RATIO u100) ;; Minimum 100% collateralization
(define-constant MAX-COLLATERAL-RATIO u500) ;; Maximum 500% collateralization

;; Read-only functions
(define-read-only (get-loan (loan-id uint))
    (map-get? loans {loan-id: loan-id})
)

(define-read-only (get-user-balance (user principal))
    (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-collateral-ratio (collateral uint) (loan-amount uint))
    (let
        (
            (ratio (* (/ collateral loan-amount) u100))
        )
        ratio
    )
)

(define-read-only (get-total-stx-locked)
    (var-get total-stx-locked)
)

;; Private functions
(define-private (update-user-balance (user principal) (amount uint) (add bool))
    (let
        (
            (current-balance (get-user-balance user))
            (new-balance (if add
                (+ current-balance amount)
                (- current-balance amount)))
        )
        (map-set user-balances user new-balance)
        (ok new-balance)
    )
)

;; Validation function for interest rate
(define-private (is-valid-interest-rate (rate uint))
    (and (> rate u0) (<= rate MAX-INTEREST-RATE))
)

;; Validation function for duration
(define-private (is-valid-duration (duration uint))
    (and (> duration u0) (<= duration MAX-LOAN-DURATION))
)

;; Validation function for collateral ratio
(define-private (is-valid-collateral-ratio (ratio uint))
    (and (>= ratio MIN-COLLATERAL-RATIO) (<= ratio MAX-COLLATERAL-RATIO))
)

;; Public functions
(define-public (create-loan (amount uint) (collateral uint) (interest-rate uint) (duration uint))
    (let
        (
            (loan-id (var-get next-loan-id))
            (collateral-ratio (get-collateral-ratio collateral amount))
        )
        ;; Enhanced input validations
        (asserts! (> amount u0) ERR-INVALID-PRINCIPAL)
        (asserts! (is-valid-interest-rate interest-rate) ERR-INVALID-INTEREST-RATE)
        (asserts! (is-valid-duration duration) ERR-INVALID-DURATION)
        (asserts! (>= collateral-ratio (var-get minimum-collateral-ratio)) ERR-INSUFFICIENT-COLLATERAL)
        
        (try! (stx-transfer? collateral tx-sender (as-contract tx-sender)))
        
        ;; Update total STX locked
        (var-set total-stx-locked (+ (var-get total-stx-locked) collateral))
        
        ;; Create new loan
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
                status: "PENDING"
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
        (asserts! (is-eq (get status loan) "PENDING") ERR-LOAN-ALREADY-ACTIVE)
        (try! (stx-transfer? amount tx-sender (get borrower loan)))
        
        ;; Update loan status
        (map-set loans
            {loan-id: loan-id}
            (merge loan {
                lender: (some tx-sender),
                start-height: block-height,
                status: "ACTIVE"
            })
        )
        (ok true)
    )
)

(define-public (repay-loan (loan-id uint))
    (let
        (
            (loan (unwrap! (get-loan loan-id) ERR-LOAN-NOT-FOUND))
            (total-amount (+ (get amount loan) 
                           (/ (* (get amount loan) (get interest-rate loan)) u100)))
            (lender (unwrap! (get lender loan) ERR-LOAN-NOT-FOUND))
        )
        (asserts! (is-eq (get status loan) "ACTIVE") ERR-LOAN-NOT-FOUND)
        (asserts! (is-eq (get borrower loan) tx-sender) ERR-NOT-AUTHORIZED)
        
        ;; Transfer repayment to lender
        (try! (stx-transfer? total-amount tx-sender lender))
        
        ;; Return collateral to borrower
        (as-contract
            (try! (stx-transfer? (get collateral loan) tx-sender tx-sender))
        )
        
        ;; Update total STX locked
        (var-set total-stx-locked (- (var-get total-stx-locked) (get collateral loan)))
        
        ;; Update loan status
        (map-set loans
            {loan-id: loan-id}
            (merge loan {
                status: "REPAID"
            })
        )
        (ok true)
    )
)

(define-public (liquidate-loan (loan-id uint))
    (let
        (
            (loan (unwrap! (get-loan loan-id) ERR-LOAN-NOT-FOUND))
            (loan-end-height (+ (get start-height loan) (get duration loan)))
            (lender (unwrap! (get lender loan) ERR-LOAN-NOT-FOUND))
        )
        (asserts! (is-eq (get status loan) "ACTIVE") ERR-LOAN-NOT-FOUND)
        (asserts! (>= block-height loan-end-height) ERR-LOAN-NOT-DUE)
        
        ;; Transfer collateral to lender
        (as-contract
            (try! (stx-transfer? (get collateral loan) lender tx-sender))
        )
        
        ;; Update total STX locked
        (var-set total-stx-locked (- (var-get total-stx-locked) (get collateral loan)))
        
        ;; Update loan status
        (map-set loans
            {loan-id: loan-id}
            (merge loan {
                status: "DEFAULTED"
            })
        )
        (ok true)
    )
)

;; Admin functions
(define-public (set-minimum-collateral-ratio (new-ratio uint))
    (begin
        ;; Enhanced validation for collateral ratio
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-collateral-ratio new-ratio) ERR-INVALID-RATIO)
        (var-set minimum-collateral-ratio new-ratio)
        (ok true)
    )
)

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq new-owner tx-sender)) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)