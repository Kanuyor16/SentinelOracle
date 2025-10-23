;; Automated Market Sentiment Analyzer
;; This smart contract enables decentralized market sentiment analysis by allowing users to submit
;; sentiment scores, aggregating them, and rewarding accurate predictions. It tracks historical
;; sentiment data, validates submissions, and implements a reputation-based weighting system.

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-sentiment (err u101))
(define-constant err-already-submitted (err u102))
(define-constant err-insufficient-stake (err u103))
(define-constant err-period-not-ended (err u104))
(define-constant err-no-submission (err u105))
(define-constant err-already-finalized (err u106))
(define-constant err-not-finalized (err u107))

(define-constant min-sentiment-score u1)
(define-constant max-sentiment-score u100)
(define-constant min-stake-amount u1000000) ;; 1 STX in microSTX
(define-constant reputation-multiplier u100)
(define-constant accuracy-threshold u80) ;; 80% accuracy for rewards

;; data maps and vars
;; Tracks individual sentiment submissions per period
(define-map sentiment-submissions
  {user: principal, period: uint}
  {
    sentiment-score: uint,
    confidence: uint,
    stake-amount: uint,
    timestamp: uint,
    claimed: bool
  }
)

;; Tracks user reputation and historical performance
(define-map user-reputation
  {user: principal}
  {
    total-submissions: uint,
    accurate-predictions: uint,
    reputation-score: uint,
    total-rewards: uint
  }
)

;; Tracks aggregated sentiment data per period
(define-map period-sentiment
  {period: uint}
  {
    total-weighted-sentiment: uint,
    total-weight: uint,
    participant-count: uint,
    finalized: bool,
    final-sentiment: uint,
    actual-outcome: uint
  }
)

;; Global state variables
(define-data-var current-period uint u1)
(define-data-var total-staked uint u0)
(define-data-var reward-pool uint u0)
(define-data-var period-duration uint u144) ;; ~24 hours in blocks (Bitcoin blocks)

;; private functions
;; Calculate weighted sentiment contribution based on user reputation
(define-private (calculate-weighted-score (sentiment uint) (confidence uint) (reputation uint))
  (let
    (
      (base-weight (* sentiment confidence))
      (reputation-bonus (/ (* reputation reputation-multiplier) u100))
    )
    (+ base-weight reputation-bonus)
  )
)

;; Validate sentiment score is within acceptable range
(define-private (is-valid-sentiment (score uint))
  (and (>= score min-sentiment-score) (<= score max-sentiment-score))
)

;; Calculate accuracy percentage between prediction and actual outcome
(define-private (calculate-accuracy (prediction uint) (actual uint))
  (let
    (
      (difference (if (>= prediction actual)
                     (- prediction actual)
                     (- actual prediction)))
      (accuracy-pct (- u100 difference))
    )
    (if (> accuracy-pct u100) u0 accuracy-pct)
  )
)

;; Update user reputation based on prediction accuracy
(define-private (update-user-reputation (user principal) (is-accurate bool))
  (let
    (
      (current-rep (default-to 
        {total-submissions: u0, accurate-predictions: u0, reputation-score: u50, total-rewards: u0}
        (map-get? user-reputation {user: user})))
      (new-submissions (+ (get total-submissions current-rep) u1))
      (new-accurate (if is-accurate 
                       (+ (get accurate-predictions current-rep) u1)
                       (get accurate-predictions current-rep)))
      (new-reputation (/ (* new-accurate u100) new-submissions))
    )
    (map-set user-reputation
      {user: user}
      {
        total-submissions: new-submissions,
        accurate-predictions: new-accurate,
        reputation-score: new-reputation,
        total-rewards: (get total-rewards current-rep)
      }
    )
  )
)

;; public functions
;; Submit sentiment score for current period with stake
(define-public (submit-sentiment (sentiment uint) (confidence uint))
  (let
    (
      (period (var-get current-period))
      (sender tx-sender)
      (user-rep (default-to 
        {total-submissions: u0, accurate-predictions: u0, reputation-score: u50, total-rewards: u0}
        (map-get? user-reputation {user: sender})))
      (weighted-score (calculate-weighted-score sentiment confidence (get reputation-score user-rep)))
    )
    ;; Validations
    (asserts! (is-valid-sentiment sentiment) err-invalid-sentiment)
    (asserts! (and (>= confidence u1) (<= confidence u100)) err-invalid-sentiment)
    (asserts! (is-none (map-get? sentiment-submissions {user: sender, period: period})) err-already-submitted)
    
    ;; Record submission
    (map-set sentiment-submissions
      {user: sender, period: period}
      {
        sentiment-score: sentiment,
        confidence: confidence,
        stake-amount: min-stake-amount,
        timestamp: block-height,
        claimed: false
      }
    )
    
    ;; Update period aggregates
    (let
      (
        (current-period-data (default-to
          {total-weighted-sentiment: u0, total-weight: u0, participant-count: u0, 
           finalized: false, final-sentiment: u0, actual-outcome: u0}
          (map-get? period-sentiment {period: period})))
      )
      (map-set period-sentiment
        {period: period}
        {
          total-weighted-sentiment: (+ (get total-weighted-sentiment current-period-data) weighted-score),
          total-weight: (+ (get total-weight current-period-data) confidence),
          participant-count: (+ (get participant-count current-period-data) u1),
          finalized: false,
          final-sentiment: u0,
          actual-outcome: u0
        }
      )
    )
    
    (var-set total-staked (+ (var-get total-staked) min-stake-amount))
    (ok true)
  )
)

;; Finalize period and calculate aggregate sentiment
(define-public (finalize-period (actual-outcome uint))
  (let
    (
      (period (var-get current-period))
      (period-data (unwrap! (map-get? period-sentiment {period: period}) err-no-submission))
    )
    ;; Only contract owner can finalize
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get finalized period-data)) err-already-finalized)
    (asserts! (is-valid-sentiment actual-outcome) err-invalid-sentiment)
    
    ;; Calculate final weighted sentiment
    (let
      (
        (final-sentiment (if (> (get total-weight period-data) u0)
                            (/ (get total-weighted-sentiment period-data) (get total-weight period-data))
                            u50))
      )
      (map-set period-sentiment
        {period: period}
        (merge period-data {
          finalized: true,
          final-sentiment: final-sentiment,
          actual-outcome: actual-outcome
        })
      )
      
      ;; Move to next period
      (var-set current-period (+ period u1))
      (ok final-sentiment)
    )
  )
)

;; Calculate and distribute rewards to users with accurate predictions
;; This function evaluates each user's prediction accuracy against the actual outcome,
;; determines reward eligibility, calculates proportional rewards based on stake and accuracy,
;; and updates user reputation scores accordingly
(define-public (claim-rewards (period uint))
  (let
    (
      (sender tx-sender)
      (submission (unwrap! (map-get? sentiment-submissions {user: sender, period: period}) err-no-submission))
      (period-data (unwrap! (map-get? period-sentiment {period: period}) err-no-submission))
    )
    ;; Validations
    (asserts! (get finalized period-data) err-not-finalized)
    (asserts! (not (get claimed submission)) err-already-submitted)
    
    ;; Calculate accuracy and determine reward
    (let
      (
        (prediction (get sentiment-score submission))
        (actual (get actual-outcome period-data))
        (accuracy (calculate-accuracy prediction actual))
        (is-accurate (>= accuracy accuracy-threshold))
        (base-reward (get stake-amount submission))
        (accuracy-multiplier (/ accuracy u100))
        (final-reward (if is-accurate
                         (+ base-reward (/ (* base-reward accuracy-multiplier) u2))
                         (/ base-reward u2))) ;; Partial refund if inaccurate
      )
      ;; Update submission as claimed
      (map-set sentiment-submissions
        {user: sender, period: period}
        (merge submission {claimed: true})
      )
      
      ;; Update user reputation
      (update-user-reputation sender is-accurate)
      
      ;; Update total rewards for user
      (let
        (
          (user-rep (unwrap! (map-get? user-reputation {user: sender}) err-no-submission))
        )
        (map-set user-reputation
          {user: sender}
          (merge user-rep {total-rewards: (+ (get total-rewards user-rep) final-reward)})
        )
      )
      
      ;; Update global state
      (var-set total-staked (- (var-get total-staked) (get stake-amount submission)))
      
      (ok final-reward)
    )
  )
)

;; Read-only functions
(define-read-only (get-current-period)
  (ok (var-get current-period))
)

(define-read-only (get-period-sentiment (period uint))
  (ok (map-get? period-sentiment {period: period}))
)

(define-read-only (get-user-submission (user principal) (period uint))
  (ok (map-get? sentiment-submissions {user: user, period: period}))
)

(define-read-only (get-user-reputation (user principal))
  (ok (map-get? user-reputation {user: user}))
)



