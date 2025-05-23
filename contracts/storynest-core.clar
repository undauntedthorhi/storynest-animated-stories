;; storynest-core
;; This contract manages the creation, ownership, trading, and monetization of animated stories as NFTs on the Stacks blockchain.
;; It implements core functionality for StoryNest, allowing creators to mint, price, and receive royalties from their stories,
;; while enabling collectors to buy, sell, and maintain libraries of animated story content.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-STORY-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-LISTED (err u102))
(define-constant ERR-NOT-LISTED (err u103))
(define-constant ERR-INVALID-PRICE (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-CANNOT-BUY-OWN-STORY (err u106))
(define-constant ERR-ROYALTY-TOO-HIGH (err u107))
(define-constant ERR-OFFER-NOT-FOUND (err u108))
(define-constant ERR-OFFER-EXPIRED (err u109))
(define-constant ERR-INVALID-METADATA (err u110))
(define-constant ERR-STORY-METADATA-FROZEN (err u111))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-ROYALTY-PERCENTAGE u300) ;; 30.0% maximum royalty (expressed as basis points)
(define-constant PLATFORM-FEE-PERCENTAGE u250) ;; 2.5% platform fee (expressed as basis points)
(define-constant BASIS-POINTS u1000) ;; Denominator for percentage calculations

;; Data structures
;; Story data
(define-map stories
  { story-id: uint }
  {
    creator: principal,
    metadata-uri: (string-utf8 256),
    royalty-percentage: uint,
    creation-time: uint,
    is-metadata-frozen: bool
  }
)

;; Story ownership
(define-map story-owners
  { story-id: uint }
  { owner: principal }
)

;; Stories created by a specific creator
(define-map creator-stories
  { creator: principal }
  { story-ids: (list 100 uint) }
)

;; Stories owned by a specific collector
(define-map collector-stories
  { collector: principal }
  { story-ids: (list 100 uint) }
)

;; Story marketplace listings
(define-map story-listings
  { story-id: uint }
  {
    price: uint,
    lister: principal,
    list-time: uint
  }
)

;; Offers made on stories
(define-map story-offers
  { story-id: uint, offerer: principal }
  {
    price: uint,
    expiry: uint
  }
)

;; NFT counter for story IDs
(define-data-var last-story-id uint u0)

;; Private functions
;; Calculates the royalty amount for a sale
(define-private (calculate-royalty (price uint) (royalty-percentage uint))
  (/ (* price royalty-percentage) BASIS-POINTS)
)

;; Calculates the platform fee for a sale
(define-private (calculate-platform-fee (price uint))
  (/ (* price PLATFORM-FEE-PERCENTAGE) BASIS-POINTS)
)

;; Adds a story ID to a list, avoiding duplicates
(define-private (add-story-to-list (story-id uint) (story-list (list 100 uint)))
  (if (is-some (index-of story-list story-id))
    story-list
    (unwrap-panic (as-max-len? (append story-list story-id) u100))
  )
)



;; Updates a creator's stories list
(define-private (update-creator-stories (creator principal) (story-id uint))
  (let ((current-stories (default-to { story-ids: (list) } (map-get? creator-stories { creator: creator }))))
    (map-set creator-stories
      { creator: creator }
      { story-ids: (add-story-to-list story-id (get story-ids current-stories)) }
    )
  )
)

;; Updates a collector's stories list
(define-private (update-collector-stories (collector principal) (story-id uint))
  (let ((current-stories (default-to { story-ids: (list) } (map-get? collector-stories { collector: collector }))))
    (map-set collector-stories
      { collector: collector }
      { story-ids: (add-story-to-list story-id (get story-ids current-stories)) }
    )
  )
)




;; Read-only functions
;; Returns story data
(define-read-only (get-story (story-id uint))
  (map-get? stories { story-id: story-id })
)

;; Returns story owner
(define-read-only (get-story-owner (story-id uint))
  (map-get? story-owners { story-id: story-id })
)

;; Returns listing information for a story
(define-read-only (get-story-listing (story-id uint))
  (map-get? story-listings { story-id: story-id })
)

;; Returns all stories created by a specific creator
(define-read-only (get-creator-stories (creator principal))
  (default-to { story-ids: (list) } (map-get? creator-stories { creator: creator }))
)

;; Returns all stories owned by a specific collector
(define-read-only (get-collector-stories (collector principal))
  (default-to { story-ids: (list) } (map-get? collector-stories { collector: collector }))
)

;; Returns information about an offer made on a story
(define-read-only (get-story-offer (story-id uint) (offerer principal))
  (map-get? story-offers { story-id: story-id, offerer: offerer })
)

;; Checks if a principal is the owner of a story
(define-read-only (is-story-owner (story-id uint) (user principal))
  (let ((owner-data (map-get? story-owners { story-id: story-id })))
    (and (is-some owner-data) (is-eq (get owner (default-to { owner: CONTRACT-OWNER } owner-data)) user))
  )
)

;; Public functions
;; Creates a new story NFT
(define-public (create-story (metadata-uri (string-utf8 256)) (royalty-percentage uint))
  (let (
    (new-story-id (+ (var-get last-story-id) u1))
    (caller tx-sender)
  )
    ;; Validate inputs
    (asserts! (<= royalty-percentage MAX-ROYALTY-PERCENTAGE) ERR-ROYALTY-TOO-HIGH)
    (asserts! (> (len metadata-uri) u0) ERR-INVALID-METADATA)
    
    ;; Update data maps
    (map-set stories
      { story-id: new-story-id }
      {
        creator: caller,
        metadata-uri: metadata-uri,
        royalty-percentage: royalty-percentage,
        creation-time: block-height,
        is-metadata-frozen: false
      }
    )
    
    ;; Set initial ownership
    (map-set story-owners
      { story-id: new-story-id }
      { owner: caller }
    )
    
    ;; Update creator's stories
    (update-creator-stories caller new-story-id)
    
    ;; Update collector's stories (creator is the first collector)
    (update-collector-stories caller new-story-id)
    
    ;; Update story counter
    (var-set last-story-id new-story-id)
    
    ;; Return the new story ID
    (ok new-story-id)
  )
)

;; Updates a story's metadata, if permitted
(define-public (update-story-metadata (story-id uint) (new-metadata-uri (string-utf8 256)))
  (let (
    (story-data (unwrap! (map-get? stories { story-id: story-id }) ERR-STORY-NOT-FOUND))
    (creator (get creator story-data))
    (is-frozen (get is-metadata-frozen story-data))
  )
    ;; Check authorization and metadata state
    (asserts! (is-eq tx-sender creator) ERR-NOT-AUTHORIZED)
    (asserts! (not is-frozen) ERR-STORY-METADATA-FROZEN)
    (asserts! (> (len new-metadata-uri) u0) ERR-INVALID-METADATA)
    
    ;; Update the metadata
    (map-set stories
      { story-id: story-id }
      (merge story-data { metadata-uri: new-metadata-uri })
    )
    
    (ok true)
  )
)

;; Permanently freezes a story's metadata so it can't be changed
(define-public (freeze-story-metadata (story-id uint))
  (let (
    (story-data (unwrap! (map-get? stories { story-id: story-id }) ERR-STORY-NOT-FOUND))
    (creator (get creator story-data))
  )
    ;; Check authorization
    (asserts! (is-eq tx-sender creator) ERR-NOT-AUTHORIZED)
    
    ;; Freeze the metadata
    (map-set stories
      { story-id: story-id }
      (merge story-data { is-metadata-frozen: true })
    )
    
    (ok true)
  )
)

;; Lists a story for sale
(define-public (list-story (story-id uint) (price uint))
  (let (
    (owner-data (unwrap! (map-get? story-owners { story-id: story-id }) ERR-STORY-NOT-FOUND))
    (owner (get owner owner-data))
    (existing-listing (map-get? story-listings { story-id: story-id }))
  )
    ;; Validate inputs and authorization
    (asserts! (is-eq tx-sender owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-none existing-listing) ERR-ALREADY-LISTED)
    (asserts! (> price u0) ERR-INVALID-PRICE)
    
    ;; Create the listing
    (map-set story-listings
      { story-id: story-id }
      {
        price: price,
        lister: tx-sender,
        list-time: block-height
      }
    )
    
    (ok true)
  )
)

;; Cancels a story listing
(define-public (cancel-listing (story-id uint))
  (let (
    (listing (unwrap! (map-get? story-listings { story-id: story-id }) ERR-NOT-LISTED))
    (lister (get lister listing))
  )
    ;; Check authorization
    (asserts! (is-eq tx-sender lister) ERR-NOT-AUTHORIZED)
    
    ;; Remove the listing
    (map-delete story-listings { story-id: story-id })
    
    (ok true)
  )
)


;; Makes an offer on a story
(define-public (make-offer (story-id uint) (offer-price uint) (expiry uint))
  (let (
    (owner-data (unwrap! (map-get? story-owners { story-id: story-id }) ERR-STORY-NOT-FOUND))
    (owner (get owner owner-data))
    (offerer tx-sender)
  )
    ;; Validate inputs
    (asserts! (not (is-eq offerer owner)) ERR-CANNOT-BUY-OWN-STORY)
    (asserts! (> offer-price u0) ERR-INVALID-PRICE)
    (asserts! (> expiry block-height) ERR-OFFER-EXPIRED)
    
    ;; Store the offer
    (map-set story-offers
      { story-id: story-id, offerer: offerer }
      {
        price: offer-price,
        expiry: expiry
      }
    )
    
    (ok true)
  )
)

;; Cancels an offer on a story
(define-public (cancel-offer (story-id uint))
  (begin
    ;; Check that the offer exists
    (asserts! (is-some (map-get? story-offers { story-id: story-id, offerer: tx-sender })) ERR-OFFER-NOT-FOUND)
    
    ;; Delete the offer
    (map-delete story-offers { story-id: story-id, offerer: tx-sender })
    
    (ok true)
  )
)


