;; Fleet Management System
;; Spaceships that upgrade based on cosmic events and pilot experience

;; Define the Spaceship NFT
(define-non-fungible-token cosmic-vessel uint)

;; Constants
(define-constant fleet-commander tx-sender)
(define-constant err-commander-only (err u200))
(define-constant err-not-pilot (err u201))
(define-constant err-vessel-not-found (err u202))
(define-constant err-already-launched (err u203))

;; Data Variables
(define-data-var last-vessel-id uint u0)
(define-data-var solar-storm-threshold uint u75000) ;; Cosmic energy threshold
(define-data-var shipyard-commission uint u300) ;; 3% commission (300 basis points)

;; Data Maps
(define-map vessel-specs 
  uint 
  {
    model: (string-ascii 64),
    mission-log: (string-ascii 256),
    blueprint-uri: (string-ascii 256),
    upgrade-tier: uint,
    last-upgrade-stardate: uint,
    pilot-experience: uint,
    mission-count: uint
  }
)

(define-map vessel-market-value uint uint)
(define-map pilot-mission-log principal uint)
(define-map cosmic-energy-readings uint uint) ;; Stardate -> Energy level

;; Helper Functions
(define-private (get-next-vessel-id)
  (+ (var-get last-vessel-id) u1)
)

(define-private (calculate-upgrade-tier (cosmic-energy uint) (pilot-exp uint) (stardates-owned uint))
  (let ((energy-boost (if (>= cosmic-energy (var-get solar-storm-threshold)) u2 u1))
        (exp-boost (/ pilot-exp u10))
        (time-boost (/ stardates-owned u1000)))
    (+ energy-boost exp-boost time-boost)
  )
)

(define-private (update-pilot-experience (pilot principal))
  (let ((current-exp (default-to u0 (map-get? pilot-mission-log pilot))))
    (map-set pilot-mission-log pilot (+ current-exp u1))
    (+ current-exp u1)
  )
)

;; Public Functions

;; Launch a new cosmic vessel
(define-public (launch-vessel (pilot principal) (model (string-ascii 64)) (mission-log (string-ascii 256)) (blueprint-uri (string-ascii 256)))
  (let ((vessel-id (get-next-vessel-id)))
    (begin
      (try! (nft-mint? cosmic-vessel vessel-id pilot))
      (map-set vessel-specs vessel-id {
        model: model,
        mission-log: mission-log,
        blueprint-uri: blueprint-uri,
        upgrade-tier: u1,
        last-upgrade-stardate: block-height,
        pilot-experience: u0,
        mission-count: u0
      })
      (var-set last-vessel-id vessel-id)
      (ok vessel-id)
    )
  )
)

;; List vessel in shipyard
(define-public (dock-for-sale (vessel-id uint) (asking-price uint))
  (let ((pilot (unwrap! (nft-get-owner? cosmic-vessel vessel-id) err-vessel-not-found)))
    (begin
      (asserts! (is-eq pilot tx-sender) err-not-pilot)
      (map-set vessel-market-value vessel-id asking-price)
      (ok true)
    )
  )
)

;; Purchase vessel from shipyard
(define-public (acquire-vessel (vessel-id uint))
  (let ((price (unwrap! (map-get? vessel-market-value vessel-id) err-vessel-not-found))
        (current-pilot (unwrap! (nft-get-owner? cosmic-vessel vessel-id) err-vessel-not-found))
        (commission (/ (* price (var-get shipyard-commission)) u10000))
        (pilot-payment (- price commission)))
    (begin
      ;; Transfer payment to current pilot
      (try! (stx-transfer? pilot-payment tx-sender current-pilot))
      ;; Transfer commission to fleet commander
      (try! (stx-transfer? commission tx-sender fleet-commander))
      ;; Transfer vessel to new pilot
      (try! (nft-transfer? cosmic-vessel vessel-id current-pilot tx-sender))
      ;; Remove from market
      (map-delete vessel-market-value vessel-id)
      ;; Update pilot experience
      (update-pilot-experience tx-sender)
      (ok true)
    )
  )
)

;; Update cosmic energy readings (only fleet commander)
(define-public (record-cosmic-energy (energy-level uint))
  (begin
    (asserts! (is-eq tx-sender fleet-commander) err-commander-only)
    (map-set cosmic-energy-readings block-height energy-level)
    (ok true)
  )
)

;; Upgrade vessel based on cosmic conditions
(define-public (upgrade-vessel (vessel-id uint))
  (let ((vessel-data (unwrap! (map-get? vessel-specs vessel-id) err-vessel-not-found))
        (pilot (unwrap! (nft-get-owner? cosmic-vessel vessel-id) err-vessel-not-found))
        (current-cosmic-energy (default-to u65000 (map-get? cosmic-energy-readings block-height)))
        (pilot-exp (default-to u0 (map-get? pilot-mission-log pilot)))
        (stardates-owned (- block-height (get last-upgrade-stardate vessel-data)))
        (new-upgrade-tier (calculate-upgrade-tier current-cosmic-energy pilot-exp stardates-owned)))
    (begin
      ;; Must own vessel for at least 100 stardates
      (asserts! (> stardates-owned u100) (err u204))
      ;; Must actually upgrade
      (asserts! (> new-upgrade-tier (get upgrade-tier vessel-data)) (err u205))
      
      ;; Update vessel specifications
      (map-set vessel-specs vessel-id (merge vessel-data {
        upgrade-tier: new-upgrade-tier,
        last-upgrade-stardate: block-height,
        pilot-experience: pilot-exp,
        mission-count: (+ (get mission-count vessel-data) u1)
      }))
      
      ;; Update pilot experience
      (update-pilot-experience pilot)
      (ok new-upgrade-tier)
    )
  )
)

;; Conduct mission with vessel
(define-public (conduct-mission (vessel-id uint))
  (let ((pilot (unwrap! (nft-get-owner? cosmic-vessel vessel-id) err-vessel-not-found)))
    (begin
      (asserts! (is-eq pilot tx-sender) err-not-pilot)
      (let ((new-exp (update-pilot-experience tx-sender)))
        (ok new-exp)
      )
    )
  )
)

;; Read-only functions

(define-read-only (get-vessel-specs (vessel-id uint))
  (map-get? vessel-specs vessel-id)
)

(define-read-only (get-vessel-price (vessel-id uint))
  (map-get? vessel-market-value vessel-id)
)

(define-read-only (get-pilot-experience (pilot principal))
  (default-to u0 (map-get? pilot-mission-log pilot))
)

(define-read-only (get-current-cosmic-energy)
  (default-to u65000 (map-get? cosmic-energy-readings block-height))
)

(define-read-only (get-fleet-size)
  (var-get last-vessel-id)
)

(define-read-only (get-vessel-pilot (vessel-id uint))
  (ok (nft-get-owner? cosmic-vessel vessel-id))
)

;; Initialize space station
(define-public (initialize-starbase)
  (begin
    (asserts! (is-eq tx-sender fleet-commander) err-commander-only)
    (map-set cosmic-energy-readings block-height u75000)
    (ok true)
  )
)