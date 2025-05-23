# StoryNest Animated Stories

A decentralized platform for creating, collecting, and licensing animated stories as NFTs on the Stacks blockchain.

## Overview

StoryNest enables creators to:
- Publish animated stories as unique NFTs
- Set pricing and royalties for their work
- Offer tiered commercial licensing (personal, commercial, derivative)
- Earn ongoing revenue through secondary sales and licensing

Collectors can:
- Build personal libraries of animated stories
- Support creators through direct purchases
- Trade stories on the secondary market
- Acquire commercial usage rights through the licensing system

## Architecture

The platform consists of two main smart contracts that handle core functionality and licensing:

```mermaid
graph TD
    A[StoryNest Core Contract] --> B[Story Creation]
    A --> C[Ownership Management]
    A --> D[Trading System]
    A --> E[Royalty Distribution]
    
    F[Licensing Contract] --> G[License Configuration]
    F --> H[License Issuance]
    F --> I[License Verification]
    F --> J[License Management]
    
    B --> K[Creator Economy]
    C --> K
    D --> K
    E --> K
    G --> L[Commercial Usage]
    H --> L
    I --> L
    J --> L
```

## Contract Documentation

### StoryNest Core (`storynest-core.clar`)

The core contract manages the fundamental NFT functionality:

- Story creation and ownership
- Trading mechanics (listing, buying, offering)
- Royalty distribution
- Metadata management

Key features:
- Configurable royalty percentages (up to 30%)
- 2.5% platform fee on transactions
- Metadata freezing capability
- Secondary market support

### Licensing (`storynest-licensing.clar`)

Handles commercial licensing and usage rights:

- Three license tiers: Personal, Commercial, Derivative
- Configurable pricing and duration
- License verification system
- Usage tracking and management

## Getting Started

### Prerequisites
- Clarinet
- Stacks wallet
- STX tokens for transactions

### Basic Usage

1. Creating a story:
```clarity
(contract-call? .storynest-core create-story "metadata-uri" u100)
```

2. Listing a story for sale:
```clarity
(contract-call? .storynest-core list-story story-id price)
```

3. Configuring a license:
```clarity
(contract-call? .storynest-licensing configure-license-tier story-id token-id tier price duration-days max-licenses)
```

## Function Reference

### Core Contract Functions

#### Story Management
```clarity
(create-story (metadata-uri (string-utf8 256)) (royalty-percentage uint))
(update-story-metadata (story-id uint) (new-metadata-uri (string-utf8 256)))
(freeze-story-metadata (story-id uint))
```

#### Trading
```clarity
(list-story (story-id uint) (price uint))
(buy-story (story-id uint))
(make-offer (story-id uint) (offer-price uint) (expiry uint))
(accept-offer (story-id uint) (offerer principal))
```

### Licensing Functions

#### License Management
```clarity
(configure-license-tier (story-id uint) (token-id uint) (tier uint) (price uint) (duration-days uint) (max-licenses (optional uint)))
(purchase-license (story-id uint) (token-id uint) (tier uint))
(renew-license (story-id uint) (token-id uint) (tier uint))
(revoke-license (story-id uint) (token-id uint) (tier uint) (licensee principal))
```

## Development

### Testing
Run tests using Clarinet:
```bash
clarinet test
```

### Local Development
1. Start local chain:
```bash
clarinet integrate
```

2. Deploy contracts:
```bash
clarinet deploy
```

## Security Considerations

### Core Contract
- Royalty calculations use basis points to avoid floating-point issues
- Ownership checks prevent unauthorized transfers
- Metadata freezing prevents post-sale modifications

### Licensing Contract
- License validation prevents unauthorized usage
- Expiration tracking ensures proper access control
- Creator-only license configuration and revocation
- Maximum license count enforcement

### General
- All financial transactions verify sufficient funds
- Access control checks on privileged operations
- State changes are atomic and consistent