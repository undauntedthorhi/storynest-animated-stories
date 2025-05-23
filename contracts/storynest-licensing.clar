;; storynest-licensing
;; 
;; This contract manages commercial licensing rights and usage permissions for StoryNest animated stories.
;; It enables creators to define and sell different tiers of usage rights (personal, commercial, derivative)
;; separate from NFT ownership, creating additional revenue streams and flexible commercial applications
;; while maintaining clear permission structures.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-LICENSE-TIER (err u101))
(define-constant ERR-INVALID-DURATION (err u102))
(define-constant ERR-LICENSE-NOT-FOUND (err u103))
(define-constant ERR-LICENSE-EXPIRED (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-ALREADY-LICENSED (err u106))
(define-constant ERR-NOT-CREATOR (err u107))
(define-constant ERR-NFT-NOT-FOUND (err u108))
(define-constant ERR-INVALID-PRICE (err u109))

;; License tiers
(define-constant LICENSE-PERSONAL u1)
(define-constant LICENSE-COMMERCIAL u2)
(define-constant LICENSE-DERIVATIVE u3)

;; Contract admin
(define-data-var contract-owner principal tx-sender)

;; Data maps
;; Maps NFT ID to its creator
(define-map nft-creators {story-id: uint, token-id: uint} {creator: principal})

;; Maps NFT ID to license tier configuration
(define-map license-configurations 
  {story-id: uint, token-id: uint, tier: uint} 
  {
    price: uint,              ;; Price in STX
    duration-days: uint,      ;; Duration in days
    max-licenses: (optional uint), ;; Maximum number of licenses (optional)
    active: bool              ;; Whether this tier is available
  }
)

;; Tracks how many licenses have been issued for a specific NFT and tier
(define-map license-counts
  {story-id: uint, token-id: uint, tier: uint}
  {count: uint}
)

;; Maps active licenses
(define-map active-licenses
  {story-id: uint, token-id: uint, tier: uint, licensee: principal}
  {
    expiration: uint,         ;; Block height when license expires
    created-at: uint,         ;; Block height when license was created
    revoked: bool,            ;; If license has been revoked
    license-id: uint          ;; Unique license identifier
  }
)

;; Counter for generating unique license IDs
(define-data-var next-license-id uint u1)

;; Private functions

;; Get current license count for a specific NFT and tier
(define-private (get-license-count (story-id uint) (token-id uint) (tier uint))
  (default-to {count: u0} (map-get? license-counts {story-id: story-id, token-id: token-id, tier: tier}))
)

;; Check if a tier is valid
(define-private (is-valid-tier (tier uint))
  (or 
    (is-eq tier LICENSE-PERSONAL)
    (is-eq tier LICENSE-COMMERCIAL)
    (is-eq tier LICENSE-DERIVATIVE)
  )
)

;; Check if sender is the story creator
(define-private (is-creator (story-id uint) (token-id uint))
  (match (map-get? nft-creators {story-id: story-id, token-id: token-id})
    creator (is-eq tx-sender (get creator creator))
    false
  )
)

;; Check if a license is available for purchase
(define-private (is-license-available (story-id uint) (token-id uint) (tier uint))
  (match (map-get? license-configurations {story-id: story-id, token-id: token-id, tier: tier})
    config 
      (let ((license-count (get count (get-license-count story-id token-id tier))))
        (and 
          (get active config)
          (match (get max-licenses config)
            max-count (< license-count max-count)
            true
          )
        )
    )
    false
  )
)

;; Check if a license is still valid
(define-private (is-license-valid (story-id uint) (token-id uint) (tier uint) (licensee principal))
  (match (map-get? active-licenses {story-id: story-id, token-id: token-id, tier: tier, licensee: licensee})
    license 
      (and 
        (not (get revoked license))
        (< block-height (get expiration license))
      )
    false
  )
)

;; Generate a new unique license ID
(define-private (generate-license-id)
  (let ((current-id (var-get next-license-id)))
    (var-set next-license-id (+ current-id u1))
    current-id
  )
)

;; Increment license count
(define-private (increment-license-count (story-id uint) (token-id uint) (tier uint))
  (let ((current-count (get count (get-license-count story-id token-id tier))))
    (map-set license-counts
      {story-id: story-id, token-id: token-id, tier: tier}
      {count: (+ current-count u1)}
    )
  )
)

;; Calculate expiration block height from duration in days
(define-private (calculate-expiration (duration-days uint))
  (+ block-height (* duration-days u144)) ;; ~144 blocks per day
)

;; Read-only functions

;; Check if an address has a valid license
(define-read-only (has-valid-license (story-id uint) (token-id uint) (tier uint) (licensee principal))
  (is-license-valid story-id token-id tier licensee)
)

;; Get license configuration
(define-read-only (get-license-configuration (story-id uint) (token-id uint) (tier uint))
  (map-get? license-configurations {story-id: story-id, token-id: token-id, tier: tier})
)

;; Get license details
(define-read-only (get-license-details (story-id uint) (token-id uint) (tier uint) (licensee principal))
  (map-get? active-licenses {story-id: story-id, token-id: token-id, tier: tier, licensee: licensee})
)

;; Get story creator
(define-read-only (get-story-creator (story-id uint) (token-id uint))
  (map-get? nft-creators {story-id: story-id, token-id: token-id})
)

;; Verify a license for third parties
(define-read-only (verify-license (story-id uint) (token-id uint) (tier uint) (licensee principal) (license-id uint))
  (match (map-get? active-licenses {story-id: story-id, token-id: token-id, tier: tier, licensee: licensee})
    license (and 
              (is-eq (get license-id license) license-id)
              (not (get revoked license))
              (< block-height (get expiration license))
            )
    false
  )
)

;; Public functions

;; Register a story NFT creator
(define-public (register-story-creator (story-id uint) (token-id uint))
  (begin
    ;; Here you would typically check that tx-sender owns this token in the NFT contract
    ;; For this implementation, we'll skip that check and assume it's validated elsewhere
    (map-set nft-creators 
      {story-id: story-id, token-id: token-id}
      {creator: tx-sender}
    )
    (ok true)
  )
)

;; Configure license tier
(define-public (configure-license-tier (story-id uint) (token-id uint) (tier uint) (price uint) (duration-days uint) (max-licenses (optional uint)))
  (begin
    ;; Check authorization
    (asserts! (is-creator story-id token-id) ERR-NOT-CREATOR)
    
    ;; Validate inputs
    (asserts! (is-valid-tier tier) ERR-INVALID-LICENSE-TIER)
    (asserts! (> duration-days u0) ERR-INVALID-DURATION)
    (asserts! (> price u0) ERR-INVALID-PRICE)
    
    ;; Set configuration
    (map-set license-configurations
      {story-id: story-id, token-id: token-id, tier: tier}
      {
        price: price,
        duration-days: duration-days,
        max-licenses: max-licenses,
        active: true
      }
    )
    
    (ok true)
  )
)

;; Update license tier availability
(define-public (update-license-availability (story-id uint) (token-id uint) (tier uint) (active bool))
  (begin
    ;; Check authorization
    (asserts! (is-creator story-id token-id) ERR-NOT-CREATOR)
    
    ;; Validate tier
    (asserts! (is-valid-tier tier) ERR-INVALID-LICENSE-TIER)
    
    ;; Check if configuration exists
    (asserts! (is-some (map-get? license-configurations {story-id: story-id, token-id: token-id, tier: tier})) ERR-INVALID-LICENSE-TIER)
    
    ;; Update the active status
    (match (map-get? license-configurations {story-id: story-id, token-id: token-id, tier: tier})
      config (map-set license-configurations
        {story-id: story-id, token-id: token-id, tier: tier}
        (merge config {active: active})
      )
      false
    )
    
    (ok true)
  )
)

;; Purchase a license
(define-public (purchase-license (story-id uint) (token-id uint) (tier uint))
  (let (
    (license-config (unwrap! (map-get? license-configurations {story-id: story-id, token-id: token-id, tier: tier}) ERR-INVALID-LICENSE-TIER))
    (creator (unwrap! (map-get? nft-creators {story-id: story-id, token-id: token-id}) ERR-NFT-NOT-FOUND))
  )
    ;; Validate inputs and conditions
    (asserts! (is-valid-tier tier) ERR-INVALID-LICENSE-TIER)
    (asserts! (get active license-config) ERR-INVALID-LICENSE-TIER)
    (asserts! (is-license-available story-id token-id tier) ERR-INVALID-LICENSE-TIER)
    (asserts! (not (is-license-valid story-id token-id tier tx-sender)) ERR-ALREADY-LICENSED)
    
    ;; Process payment
    (let ((price (get price license-config)))
      (try! (stx-transfer? price tx-sender (get creator creator)))
      
      ;; Create license
      (let (
        (license-id (generate-license-id))
        (duration (get duration-days license-config))
        (expiration (calculate-expiration duration))
      )
        ;; Record the license
        (map-set active-licenses
          {story-id: story-id, token-id: token-id, tier: tier, licensee: tx-sender}
          {
            expiration: expiration,
            created-at: block-height,
            revoked: false,
            license-id: license-id
          }
        )
        
        ;; Update license count
        (increment-license-count story-id token-id tier)
        
        (ok license-id)
      )
    )
  )
)

;; Renew a license
(define-public (renew-license (story-id uint) (token-id uint) (tier uint))
  (let (
    (license (unwrap! (map-get? active-licenses {story-id: story-id, token-id: token-id, tier: tier, licensee: tx-sender}) ERR-LICENSE-NOT-FOUND))
    (license-config (unwrap! (map-get? license-configurations {story-id: story-id, token-id: token-id, tier: tier}) ERR-INVALID-LICENSE-TIER))
    (creator (unwrap! (map-get? nft-creators {story-id: story-id, token-id: token-id}) ERR-NFT-NOT-FOUND))
  )
    ;; Validate
    (asserts! (get active license-config) ERR-INVALID-LICENSE-TIER)
    (asserts! (not (get revoked license)) ERR-LICENSE-EXPIRED)
    
    ;; Process payment
    (let ((price (get price license-config)))
      (try! (stx-transfer? price tx-sender (get creator creator)))
      
      ;; Update license
      (let ((duration (get duration-days license-config))
            (new-expiration (calculate-expiration duration)))
        (map-set active-licenses
          {story-id: story-id, token-id: token-id, tier: tier, licensee: tx-sender}
          (merge license {expiration: new-expiration})
        )
        
        (ok true)
      )
    )
  )
)

;; Revoke a license (creator only)
(define-public (revoke-license (story-id uint) (token-id uint) (tier uint) (licensee principal))
  (let ((license (unwrap! (map-get? active-licenses {story-id: story-id, token-id: token-id, tier: tier, licensee: licensee}) ERR-LICENSE-NOT-FOUND)))
    
    ;; Check authorization
    (asserts! (is-creator story-id token-id) ERR-NOT-CREATOR)
    
    ;; Revoke the license
    (map-set active-licenses
      {story-id: story-id, token-id: token-id, tier: tier, licensee: licensee}
      (merge license {revoked: true})
    )
    
    (ok true)
  )
)

;; Transfer contract ownership
(define-public (transfer-contract-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)