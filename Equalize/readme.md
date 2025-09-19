# Music Album Royalty Distribution Smart Contract

A Stacks blockchain smart contract that enables automatic royalty distribution for music albums, allowing lead artists to manage musician contributions and automatically distribute streaming revenue based on predefined shares.

## Features

- **Album Creation**: Lead artists can register new music albums with custom streaming prices and royalty rates
- **Musician Management**: Add collaborating musicians with specific contribution shares and instrument roles
- **Automatic Royalty Distribution**: Streaming revenue is automatically split between the previous owner and musicians based on their contribution shares
- **Earnings Management**: Musicians can withdraw their accumulated royalties at any time
- **Album Control**: Lead artists can toggle album availability

## Contract Structure

### Constants

- `MAX-ROYALTY-RATE`: Maximum royalty percentage (25%)
- `TOTAL-BASIS`: Basis for percentage calculations (1000 = 100%)

### Data Structures

- **Albums**: Store album metadata, pricing, and availability
- **Musicians**: Track individual musician contributions and roles
- **Pending Earnings**: Accumulate royalty payments for withdrawal
- **Album Musicians**: Maintain lists of contributors per album

## Public Functions

### Core Album Management

#### `create-album`
```clarity
(create-album album-title streaming-price royalty-percentage)
```
Creates a new music album with the specified parameters.

**Parameters:**
- `album-title`: Album name (max 128 UTF-8 characters)
- `streaming-price`: Price in microSTX for initial purchase
- `royalty-percentage`: Percentage of streaming revenue for royalties (max 25%)

**Returns:** Album ID on success

#### `add-musician`
```clarity
(add-musician album-id musician contribution-share instrument)
```
Adds a collaborating musician to an unreleased album.

**Parameters:**
- `album-id`: Target album identifier
- `musician`: Principal address of the musician
- `contribution-share`: Share of royalties (deducted from lead artist's share)
- `instrument`: Musician's role/instrument (max 32 ASCII characters)

**Access:** Lead artist only, before album release

### Revenue Processing

#### `purchase-album`
```clarity
(purchase-album album-id)
```
Initial album purchase that marks the album as released and pays the lead artist.

**Parameters:**
- `album-id`: Album to purchase

**Payment:** Full streaming price to lead artist

#### `process-streaming-revenue`
```clarity
(process-streaming-revenue album-id previous-owner revenue)
```
Processes streaming revenue, splitting between the previous owner and musicians.

**Parameters:**
- `album-id`: Album generating revenue
- `previous-owner`: Previous album owner receiving the owner's share
- `revenue`: Total streaming revenue in microSTX

**Distribution:**
- Owner's share: `revenue * (1 - royalty-percentage)`
- Royalty pool: `revenue * royalty-percentage` (distributed among musicians)

### Earnings Management

#### `withdraw-earnings`
```clarity
(withdraw-earnings album-id)
```
Allows musicians to withdraw their accumulated royalties.

**Parameters:**
- `album-id`: Album from which to withdraw earnings

**Returns:** Amount withdrawn

#### `toggle-album-availability`
```clarity
(toggle-album-availability album-id)
```
Toggles album availability for streaming.

**Access:** Lead artist only

## Read-Only Functions

### Data Retrieval

- `get-album(album-id)`: Retrieve album information
- `get-musician(album-id, musician)`: Get musician's contribution details
- `get-pending-earnings(album-id, musician)`: Check accumulated earnings
- `get-album-musicians(album-id)`: List all musicians for an album
- `get-next-album-id()`: Get the next available album ID
- `album-exists(album-id)`: Check if album exists
- `get-total-albums()`: Get total number of albums created

## Usage Examples

### Creating an Album
```clarity
;; Create a new album with 15% royalty rate
(contract-call? .music-royalty create-album 
    u"My Greatest Hits" 
    u1000000  ;; 1 STX streaming price
    u150)     ;; 15% royalty rate
```

### Adding Musicians
```clarity
;; Add a guitarist with 30% contribution share
(contract-call? .music-royalty add-musician 
    u1                    ;; album-id
    'SP2A1B2C3D4E5F6G7H8  ;; musician address
    u300                  ;; 30% share (300/1000)
    "guitar")             ;; instrument
```

### Processing Streaming Revenue
```clarity
;; Process 0.1 STX streaming revenue
(contract-call? .music-royalty process-streaming-revenue 
    u1                    ;; album-id
    'SP1PREVIOUS2OWNER3   ;; previous owner
    u100000)              ;; 0.1 STX revenue
```

## Error Codes

- `ERR-UNAUTHORIZED-ACCESS (200)`: Caller lacks permission
- `ERR-ALBUM-NOT-EXISTS (201)`: Album ID not found
- `ERR-INVALID-PARAMETERS (202)`: Invalid input parameters
- `ERR-ALREADY-RELEASED (203)`: Operation not allowed on released album
- `ERR-INSUFFICIENT-BALANCE (204)`: Insufficient STX balance
- `ERR-NO-EARNINGS (205)`: No earnings available for withdrawal

## Security Considerations

1. **Access Control**: Only lead artists can modify their albums and add musicians
2. **Input Validation**: All parameters are validated before processing
3. **Balance Checks**: STX balances are verified before transfers
4. **Release Protection**: Musicians cannot be added after album release
5. **Share Limits**: Royalty rates are capped at 25%

## Workflow

1. **Album Creation**: Lead artist creates album with pricing and royalty rate
2. **Musician Addition**: Lead artist adds collaborating musicians with their shares
3. **Album Release**: First purchase marks album as released
4. **Revenue Processing**: Streaming revenue is automatically split
5. **Earnings Withdrawal**: Musicians withdraw accumulated royalties
