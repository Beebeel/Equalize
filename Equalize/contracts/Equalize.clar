;; Music Album Royalty Distribution Contract
;; Enables automatic royalty distribution for music albums

;; Error constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u200))
(define-constant ERR-ALBUM-NOT-EXISTS (err u201))
(define-constant ERR-INVALID-PARAMETERS (err u202))
(define-constant ERR-ALREADY-RELEASED (err u203))
(define-constant ERR-INSUFFICIENT-BALANCE (err u204))
(define-constant ERR-NO-EARNINGS (err u205))

;; Constants
(define-constant MAX-ROYALTY-RATE u250) ;; 25%
(define-constant TOTAL-BASIS u1000) ;; 100% = 1000

;; Data structures
(define-map albums
  { album-id: uint }
  {
    album-title: (string-utf8 128),
    lead-artist: principal,
    streaming-price: uint,
    royalty-percentage: uint,
    released: bool,
    available: bool
  }
)

(define-map musicians
  { album-id: uint, musician: principal }
  { contribution-share: uint, instrument: (string-ascii 32) }
)

(define-map pending-earnings
  { album-id: uint, musician: principal }
  { earnings: uint }
)

;; Store list of musicians for each album
(define-map album-musicians
  { album-id: uint }
  { musicians: (list 50 principal) }
)

(define-data-var next-album-id uint u1)

;; Register new music album
(define-public (create-album 
                (album-title (string-utf8 128))
                (streaming-price uint)
                (royalty-percentage uint))
  (let ((album-id (var-get next-album-id)))
    ;; Validate inputs
    (asserts! (> streaming-price u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= royalty-percentage MAX-ROYALTY-RATE) ERR-INVALID-PARAMETERS)
    (asserts! (> (len album-title) u0) ERR-INVALID-PARAMETERS)
    
    ;; Create album entry
    (map-set albums
      { album-id: album-id }
      {
        album-title: album-title,
        lead-artist: tx-sender,
        streaming-price: streaming-price,
        royalty-percentage: royalty-percentage,
        released: false,
        available: true
      })
    
    ;; Add lead artist as primary contributor
    (map-set musicians
      { album-id: album-id, musician: tx-sender }
      { contribution-share: TOTAL-BASIS, instrument: "lead-artist" })
    
    ;; Initialize musician list
    (map-set album-musicians
      { album-id: album-id }
      { musicians: (list tx-sender) })
    
    ;; Increment counter
    (var-set next-album-id (+ album-id u1))
    (ok album-id)))

;; Add musician to album
(define-public (add-musician
                (album-id uint)
                (musician principal)
                (contribution-share uint)
                (instrument (string-ascii 32)))
  (let ((album (unwrap! (map-get? albums { album-id: album-id }) ERR-ALBUM-NOT-EXISTS))
        (artist-data (unwrap! (map-get? musicians { album-id: album-id, musician: (get lead-artist album) }) ERR-ALBUM-NOT-EXISTS))
        (updated-artist-share (- (get contribution-share artist-data) contribution-share))
        (current-musicians (get musicians (unwrap! (map-get? album-musicians { album-id: album-id }) ERR-ALBUM-NOT-EXISTS))))
    
    ;; Validate inputs
    (asserts! (> album-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (not (is-eq musician tx-sender)) ERR-INVALID-PARAMETERS) ;; Can't add self
    (asserts! (> (len instrument) u0) ERR-INVALID-PARAMETERS)
    (asserts! (is-eq tx-sender (get lead-artist album)) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (get released album)) ERR-ALREADY-RELEASED)
    (asserts! (> contribution-share u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= contribution-share (get contribution-share artist-data)) ERR-INVALID-PARAMETERS)
    
    ;; Add musician
    (map-set musicians
      { album-id: album-id, musician: musician }
      { contribution-share: contribution-share, instrument: instrument })
    
    ;; Update lead artist's share
    (map-set musicians
      { album-id: album-id, musician: (get lead-artist album) }
      { contribution-share: updated-artist-share, instrument: "lead-artist" })
    
    ;; Add to musician list if not already present
    (begin
      (map-set album-musicians
        { album-id: album-id }
        { musicians: (unwrap! (as-max-len? (append current-musicians musician) u50) ERR-INVALID-PARAMETERS) })
      
      (ok true))))

;; Initial album purchase
(define-public (purchase-album (album-id uint))
  (let ((album (unwrap! (map-get? albums { album-id: album-id }) ERR-ALBUM-NOT-EXISTS))
        (price (get streaming-price album)))
    
    ;; Validate inputs
    (asserts! (> album-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (get available album) ERR-INVALID-PARAMETERS)
    (asserts! (not (get released album)) ERR-ALREADY-RELEASED)
    (asserts! (>= (stx-get-balance tx-sender) price) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer payment to contract
    (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
    
    ;; Mark as released
    (map-set albums
      { album-id: album-id }
      (merge album { released: true }))
    
    ;; Pay lead artist
    (begin
      (let ((lead-artist (get lead-artist album)))
        (as-contract (try! (stx-transfer? price tx-sender lead-artist))))
      
      (ok true))))

;; Process streaming revenue with royalties
(define-public (process-streaming-revenue
                (album-id uint)
                (previous-owner principal)
                (revenue uint))
  (let ((album (unwrap! (map-get? albums { album-id: album-id }) ERR-ALBUM-NOT-EXISTS))
        (royalty-cut (/ (* revenue (get royalty-percentage album)) TOTAL-BASIS))
        (owner-cut (- revenue royalty-cut)))
    
    ;; Validate inputs
    (asserts! (> album-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (not (is-eq previous-owner tx-sender)) ERR-INVALID-PARAMETERS) ;; Previous owner can't be current sender
    (asserts! (get available album) ERR-INVALID-PARAMETERS)
    (asserts! (get released album) ERR-INVALID-PARAMETERS)
    (asserts! (> revenue u0) ERR-INVALID-PARAMETERS)
    (asserts! (>= (stx-get-balance tx-sender) revenue) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer total revenue to contract
    (try! (stx-transfer? revenue tx-sender (as-contract tx-sender)))
    
    ;; Pay previous owner and distribute royalties
    (begin
      (if (> owner-cut u0)
          (as-contract (try! (stx-transfer? owner-cut tx-sender previous-owner)))
          true)
      
      ;; Distribute royalties to musicians
      (try! (allocate-streaming-royalties album-id royalty-cut))
      
      (ok true))))

;; Distribute streaming royalties to musicians (FIXED VERSION)
(define-private (allocate-streaming-royalties (album-id uint) (total-royalties uint))
  (let ((musician-list (get musicians (unwrap! (map-get? album-musicians { album-id: album-id }) ERR-ALBUM-NOT-EXISTS))))
    (begin
      (fold distribute-to-musician musician-list { album-id: album-id, total-royalties: total-royalties, success: true })
      (ok true))))

;; Helper function to distribute royalties to individual musician
(define-private (distribute-to-musician 
                (musician principal) 
                (data { album-id: uint, total-royalties: uint, success: bool }))
  (if (get success data)
      (let ((musician-data (map-get? musicians { album-id: (get album-id data), musician: musician })))
        (if (is-some musician-data)
            (let ((musician-share (get contribution-share (unwrap-panic musician-data)))
                  (musician-royalty (/ (* (get total-royalties data) musician-share) TOTAL-BASIS))
                  (current-earnings (default-to { earnings: u0 }
                                   (map-get? pending-earnings { album-id: (get album-id data), musician: musician }))))
              
              ;; Add to pending earnings
              (map-set pending-earnings
                { album-id: (get album-id data), musician: musician }
                { earnings: (+ (get earnings current-earnings) musician-royalty) })
              
              data)
            data))
      data))

;; Withdraw accumulated royalties
(define-public (withdraw-earnings (album-id uint))
  (let ((pending (unwrap! (map-get? pending-earnings { album-id: album-id, musician: tx-sender }) ERR-NO-EARNINGS))
        (amount (get earnings pending)))
    
    ;; Validate inputs
    (asserts! (> album-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (> amount u0) ERR-NO-EARNINGS)
    
    ;; Reset pending earnings
    (map-set pending-earnings
      { album-id: album-id, musician: tx-sender }
      { earnings: u0 })
    
    ;; Transfer earnings
    (as-contract (try! (stx-transfer? amount tx-sender tx-sender)))
    
    (ok amount)))

;; Toggle album availability (lead artist only)
(define-public (toggle-album-availability (album-id uint))
  (let ((album (unwrap! (map-get? albums { album-id: album-id }) ERR-ALBUM-NOT-EXISTS)))
    
    ;; Validate inputs
    (asserts! (> album-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (is-eq tx-sender (get lead-artist album)) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Toggle availability
    (map-set albums
      { album-id: album-id }
      (merge album { available: (not (get available album)) }))
    
    (ok true)))

;; Read-only functions
(define-read-only (get-album (album-id uint))
  (map-get? albums { album-id: album-id }))

(define-read-only (get-musician (album-id uint) (musician principal))
  (map-get? musicians { album-id: album-id, musician: musician }))

(define-read-only (get-pending-earnings (album-id uint) (musician principal))
  (default-to { earnings: u0 }
              (map-get? pending-earnings { album-id: album-id, musician: musician })))

(define-read-only (get-album-musicians (album-id uint))
  (map-get? album-musicians { album-id: album-id }))

(define-read-only (get-next-album-id)
  (var-get next-album-id))

(define-read-only (album-exists (album-id uint))
  (is-some (map-get? albums { album-id: album-id })))

(define-read-only (get-total-albums)
  (- (var-get next-album-id) u1))