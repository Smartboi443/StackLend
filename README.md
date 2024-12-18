# StackLend: Decentralized P2P Lending Protocol

StackLend is a decentralized peer-to-peer lending protocol built on the Stacks blockchain that enables users to lend and borrow STX tokens with collateral-backed loans. The protocol ensures secure lending operations through smart contracts with automated liquidation mechanisms and flexible repayment terms.

## Features

### Core Functionality
- **P2P Lending**: Direct lending between users without intermediaries
- **Collateral-Backed Loans**: All loans are secured with STX collateral
- **Flexible Terms**: Customizable loan duration, interest rates, and payment intervals
- **Automated Liquidation**: Protection for lenders through collateral liquidation
- **Payment Scheduling**: Structured repayment tracking with penalties for late payments

### Security Features
- Minimum collateral ratio enforcement (150%)
- Input validation for all parameters
- Automated liquidation when collateral ratio drops below threshold (130%)
- Late payment penalties (10%)
- Owner-only administrative functions

## Technical Specifications

### Constants
- `BLOCKS_PER_DAY`: 144 blocks
- `PENALTY_RATE`: 10%
- `LIQUIDATION_THRESHOLD`: 130%
- `MAX_INTEREST_RATE`: 50%
- `MIN/MAX_DURATION`: 1-365 days
- `MIN/MAX_PAYMENT_INTERVAL`: 1-30 days
- `MIN/MAX_COLLATERAL_RATIO`: 150-500%

### Loan States
- `PENDING`: Initial state after loan creation
- `ACTIVE`: Loan has been funded
- `REPAID`: Loan has been fully repaid
- `LIQUIDATED`: Collateral has been liquidated
- `DEFAULTED`: Loan has defaulted

## Usage Guide

### For Borrowers

1. **Creating a Loan**
```clarity
(contract-call? .stacklend create-loan
    amount          ;; Amount of STX to borrow
    collateral      ;; Amount of STX as collateral
    interest-rate   ;; Interest rate (in basis points, e.g., 1000 = 10%)
    duration        ;; Loan duration in blocks
    payment-interval ;; Payment interval in blocks
)
```

2. **Making Payments**
```clarity
(contract-call? .stacklend make-payment loan-id)
```

### For Lenders

1. **Funding a Loan**
```clarity
(contract-call? .stacklend fund-loan loan-id)
```

2. **Checking Loan Status**
```clarity
(contract-call? .stacklend get-loan loan-id)
```

3. **Liquidating Collateral**
```clarity
(contract-call? .stacklend check-and-liquidate loan-id)
```

### For Contract Owner

1. **Setting Minimum Collateral Ratio**
```clarity
(contract-call? .stacklend set-minimum-collateral-ratio new-ratio)
```

2. **Transferring Ownership**
```clarity
(contract-call? .stacklend transfer-ownership new-owner)
```

## Error Codes

- `ERR-NOT-AUTHORIZED (100)`: Unauthorized access attempt
- `ERR-INSUFFICIENT-BALANCE (101)`: Insufficient funds
- `ERR-LOAN-NOT-FOUND (102)`: Loan ID doesn't exist
- `ERR-LOAN-ALREADY-ACTIVE (103)`: Loan already funded
- `ERR-INSUFFICIENT-COLLATERAL (104)`: Collateral ratio too low
- `ERR-LOAN-NOT-DUE (105)`: Loan payment not yet due
- `ERR-LOAN-DEFAULTED (106)`: Loan in default state
- `ERR-INVALID-PRINCIPAL (107)`: Invalid loan amount
- `ERR-PAYMENT-TOO-SMALL (108)`: Payment below minimum
- `ERR-NO-LIQUIDATION-NEEDED (109)`: Collateral ratio above threshold
- `ERR-INVALID-INTEREST-RATE (110)`: Interest rate out of bounds
- `ERR-INVALID-DURATION (111)`: Duration out of bounds
- `ERR-INVALID-PAYMENT-INTERVAL (112)`: Payment interval out of bounds
- `ERR-INVALID-COLLATERAL-RATIO (113)`: Invalid collateral ratio
- `ERR-INVALID-AMOUNT (114)`: Invalid amount specified

## Development Setup

### Prerequisites
- Clarinet installed
- Stacks blockchain development environment
- Node.js and NPM (for testing)

### Installation
1. Clone the repository
```bash
git clone https://github.com/yourusername/stacklend.git
```

2. Install dependencies
```bash
cd stacklend
npm install
```

3. Run tests
```bash
clarinet test
```

## Testing

The contract includes comprehensive tests for all major functions. Run the test suite using:

```bash
clarinet test tests/stacklend_test.clar
```

## Security Considerations

1. **Collateral Management**
   - All loans must maintain minimum collateral ratio
   - Automatic liquidation protects lender funds
   - Collateral held in contract until loan completion

2. **Input Validation**
   - All user inputs are validated
   - Bounds checking on all parameters
   - Protected admin functions

3. **Access Control**
   - Function-level authorization checks
   - Only owner can modify protocol parameters
   - Protected ownership transfer

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


## Support

For support, please open an issue in the GitHub repository or contact the development team.

## Acknowledgments

- Stacks blockchain team
- Clarity language developers
- Community contributors