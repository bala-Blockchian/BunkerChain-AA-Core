
# BunkerChain: Maritime Registry with Account Abstraction

BunkerChain is a blockchain-based registry designed for the maritime bunkering industry. It utilizes **Account Abstraction (AA)** to replace traditional EOA-based management with programmable, gasless, and more secure smart contract wallets.

## Architecture Evolution
This project evolved through three distinct security iterations:
1. **Single AA Role:** Initial testing with the Bunker Tanker (Supplier) as a Smart Contract Wallet.
2. **Dual AA Roles:** Expanding AA functionality to both the Chief Engineer (Ship) and the Supplier (Barge).
3. **AA Management Layer:** The final and most secure architecture where a **MinimalAccount (AA)** acts as the **Owner** of the Maritime Registry.

## Security Model
The ownership chain is established as follows:
**EOA Owner (Signer)** ➔ **MinimalAccount (AA)** ➔ **MaritimeRegistryAAOwner (Logic)**

By introducing this layer, we achieve:
* **Gasless Transactions:** Users can interact via UserOperations without holding ETH.
* **Granular Verification:** Customizable signature verification through the AA wallet.
* **Administrative Integrity:** Core functions like `nominateBunker` are protected by the AA's validation logic.

## Getting Started

### Prerequisites
* [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation
```bash
forge install Cyfrin/foundry-devops --no-commit
forge install eth-infinitism/account-abstraction --no-commit

```

### Testing

To run the full end-to-end AA flow:

```bash
forge test -vvv

```

## 4. Documentation of Steps Taken

### Step 1: Initial AA Integration
We started by replacing the static `address` of the Supplier with a `MinimalAccount`. We tested if the Registry could recognize a Smart Contract Wallet as a valid caller for nominations.

### Step 2: Expanding to Dual AA Roles
We realized that in a global maritime ecosystem, both the Ship (Chief Engineer) and the Barge (Supplier) should have their own AA contracts. We updated the `finalizeBunker` function to verify signatures against the `owner()` of these AA contracts rather than just the address itself.

### Step 3: Access Control Refinement
During development, we noted that most maritime operations require administrative oversight. We updated the `nominateBunker` function with an `onlyOwner` modifier to ensure that only an authorized entity can initiate a new delivery record.

### Step 4: Final AA-Owner Architecture
To maximize decentralization and flexibility, we made the **MinimalAccount (AA) the actual Owner of the Maritime Registry**. This allows for:
* **Protocol Sovereignty**: The registry is controlled by code (the AA), not just a single private key, allowing for future upgrades like Multi-sig or Social Recovery.

## BunkerChain Progress Summary

* **Phase 1: Basic AA Integration**
Integrated `MinimalAccount` for the Barge role to test fundamental AA compatibility and entry point interactions.
* **Phase 2: Dual AA Roles**
Scaled the architecture to support two distinct roles (Chief Engineer and Supplier) as Smart Contract Wallets, enabling secure signature verification against contract owners.
* **Phase 3: Refined Access Control**
Enhanced security by moving the `nominateBunker` function under `onlyOwner` oversight. This ensures that only the administrative authority can initiate official maritime records.
* **Phase 4 (Final): AA-Owner Hierarchy**
Established a programmable governance model where the **Maritime Registry is owned by a MinimalAccount**.

---

## Final Architecture Documentation

### The Execution Flow

The system operates through a hierarchical authorization chain:
**Owner EOA (Signs)** ➔ **MinimalAccount AA (Executes)** ➔ **MaritimeRegistryAAOwner (Action)**

### Key Advantages

* **Gasless UX:** By utilizing the `EntryPoint`, the Barge or Chief Engineer can perform operations without holding native gas, as a Paymaster can be introduced to cover fees.
* **Signature Verification:** Signatures are verified against the **Owner** of the AA contract, allowing for flexible security (e.g., changing the signer without changing the registered maritime address).
* **Programmable Admin:** The Registry's administrative functions are now as flexible as the AA wallet itself, supporting logic like multi-sig approvals or time-locked actions.

---