# 💰 Budget Commitment Contracts

A Clarity smart contract that helps users control their spending by locking up funds and requiring approvals for expenditures.

## 🚀 Features

- 🔒 **Lock Funds**: Users can lock STX tokens to prevent overspending
- 👥 **Approval System**: Designate an approver who must authorize spending requests
- 📊 **Spending Limits**: Set maximum spending limits within your budget
- ✅ **Request & Approve**: Submit spending requests with reasons and get approvals
- 💸 **Execute Spending**: Transfer approved amounts to recipients
- 🔓 **Withdraw Remaining**: Retrieve unused locked funds

## 📋 Usage

### Creating a Budget Commitment

```clarity
(contract-call? .budget-commitment-contracts create-commitment u1000000 u500000 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

- **locked-amount**: Amount of STX to lock (in microSTX)
- **spending-limit**: Maximum allowed spending
- **approver**: Principal who can approve spending requests

### Requesting to Spend

```clarity
(contract-call? .budget-commitment-contracts request-spending u100000 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 "Office supplies")
```

- **amount**: Amount to spend (in microSTX)
- **recipient**: Who receives the funds
- **reason**: Description of the expense

### Approving a Request

```clarity
(contract-call? .budget-commitment-contracts approve-spending 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u1)
```

- **user**: The user who made the request
- **request-id**: ID of the spending request

### Executing Approved Spending

```clarity
(contract-call? .budget-commitment-contracts execute-spending u1)
```

- **request-id**: ID of the approved request

### Withdrawing Remaining Funds

```clarity
(contract-call? .budget-commitment-contracts withdraw-remaining)
```

### Viewing Data

```clarity
;; Get commitment details
(contract-call? .budget-commitment-contracts get-commitment 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

;; Get pending request
(contract-call? .budget-commitment-contracts get-pending-request 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u1)

;; Get next request ID
(contract-call? .budget-commitment-contracts get-next-request-id 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

## 🛠️ Development

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet)
- Node.js (for testing)

### Running Tests

```bash
clarinet test
```

### Deploying

```bash
clarinet deploy
```

## 📖 Contract Functions

### Public Functions

- `create-commitment` - Lock funds with spending limits and approver
- `request-spending` - Submit a spending request
- `approve-spending` - Approve a pending request (approver only)
- `execute-spending` - Execute an approved spending request
- `withdraw-remaining` - Withdraw unused locked funds
- `deactivate-commitment` - Deactivate the commitment

### Read-Only Functions

- `get-commitment` - Get commitment details for a user
- `get-pending-request` - Get details of a pending request
- `get-next-request-id` - Get the next available request ID

## 🔧 Error Codes

- `u100` - Owner only
- `u101` - Not found
- `u102` - Insufficient funds
- `u103` - Unauthorized
- `u104` - Already exists
- `u105` - Invalid amount
- `u106` - Commitment locked
- `u107` - Spending limit exceeded

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
