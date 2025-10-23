SentinelOracle
--------------

📝 Description
--------------

I've developed **SentinelOracle**, an Automated Market Sentiment Analyzer smart contract written in **Clarity**. This contract creates a decentralized mechanism for crowdsourcing and aggregating market sentiment, providing a weighted, community-driven prediction. It incentivizes accurate predictions through a staking and reward system and incorporates a **reputation-based weighting system** to prioritize input from historically accurate users. SentinelOracle is designed to operate over discrete time **periods**, tracking individual submissions, calculating an aggregated final sentiment, and rewarding participants whose predictions closely match the eventual "actual outcome" of the period (which is supplied by an authorized oracle/owner).

* * * * *

🏗️ Core Features
-----------------

-   **Decentralized Submission:** Users can submit their sentiment score (u1 to u100) and an optional confidence level for the current period by staking a minimum amount of microSTX.

-   **Reputation Weighting:** Submissions are weighted by the user's historical accuracy (Reputation Score) and their stated confidence level, ensuring that input from proven predictors carries more influence in the final aggregate.

-   **Period Finalization:** A contract owner (or designated oracle) finalizes each period by providing the "actual outcome" and triggering the calculation of the final aggregated sentiment.

-   **Incentivized Accuracy:** Participants with predictions that meet a high **accuracy threshold** ($\ge 80\%$ difference) are rewarded with their stake back plus a bonus proportional to their accuracy. Inaccurate predictors receive a partial refund (50% of their stake).

-   **Historical Tracking:** The contract tracks sentiment submissions, period aggregates, and individual user reputation over time.

-   **Clarity Smart Contract:** Built on the Stacks blockchain, ensuring transparent, deterministic, and secure execution.

* * * * *

📜 Contract Structure and Logic
-------------------------------

### Data Structures

The contract uses three primary maps to manage state:

| **Map Name** | **Key Structure** | **Value Structure** | **Description** |
| --- | --- | --- | --- |
| `sentiment-submissions` | `{user: principal, period: uint}` | `{sentiment-score: uint, confidence: uint, stake-amount: uint, timestamp: uint, claimed: bool}` | Records each user's specific submission for a given period. |
| `user-reputation` | `{user: principal}` | `{total-submissions: uint, accurate-predictions: uint, reputation-score: uint, total-rewards: uint}` | Stores the user's historical performance, crucial for weighting their current submissions. |
| `period-sentiment` | `{period: uint}` | `{total-weighted-sentiment: uint, total-weight: uint, participant-count: uint, finalized: bool, final-sentiment: uint, actual-outcome: uint}` | Aggregates all submissions for a period, storing the calculated community sentiment and the eventual actual outcome. |

* * * * *

### Global Variables

| **Variable Name** | **Type** | **Initial Value** | **Description** |
| --- | --- | --- | --- |
| `current-period` | `uint` | `u1` | The period currently open for submissions. |
| `total-staked` | `uint` | `u0` | Total STX staked across all open periods. |
| `reward-pool` | `uint` | `u0` | Placeholder for a future reward pool (currently rewards are calculated from stake). |
| `period-duration` | `uint` | `u144` | Target duration of a period in Bitcoin blocks (approx. 24 hours). |

* * * * *

### 🔒 Private Functions (Internal Helpers)

Private functions are internal to the contract and cannot be called directly by external users. They encapsulate core logic, ensuring code reusability and correctness.

#### `(calculate-weighted-score (sentiment uint) (confidence uint) (reputation uint))`

-   **Purpose:** Determines the weight of a user's sentiment submission by factoring in their confidence and historical reputation. This is critical for generating a more reliable aggregate sentiment.

-   Logic: Combines the base weight (sentiment multiplied by confidence) with a reputation bonus calculated from the user's reputation-score.

    $$\text{WeightedScore} = (\text{Sentiment} \times \text{Confidence}) + \left(\frac{\text{Reputation} \times 100}{100}\right)$$

#### `(is-valid-sentiment (score uint))`

-   **Purpose:** Ensures any submitted sentiment score or the `actual-outcome` is within the acceptable boundaries.

-   **Logic:** Returns `true` if the score is $\ge$ `min-sentiment-score` (**u1**) and $\le$ `max-sentiment-score` (**u100**).

#### `(calculate-accuracy (prediction uint) (actual uint))`

-   **Purpose:** Measures how close a user's prediction was to the final actual outcome of the period.

-   Logic: Calculates the absolute difference between the prediction and the actual outcome, then subtracts this difference from 100 to yield a percentage score.

    $$\text{Accuracy} = 100 - |\text{Prediction} - \text{ActualOutcome}|$$

#### `(update-user-reputation (user principal) (is-accurate bool))`

-   **Purpose:** Updates the user's historical performance metrics after a period is claimed.

-   **Logic:** Increments the user's `total-submissions` and conditionally increments `accurate-predictions` if `is-accurate` is true. The `reputation-score` is then updated to reflect the new accuracy percentage.

* * * * *

### Core Public Functions (Entrypoints)

#### `(define-public (submit-sentiment (sentiment uint) (confidence uint)))`

-   **Purpose:** Allows users to record their sentiment and stake collateral.

-   **State Update:** Records the submission in `sentiment-submissions` and updates the aggregate totals in `period-sentiment` using the calculated weighted score. The sender's `min-stake-amount` (u1,000,000 microSTX) is added to `total-staked`.

#### `(define-public (finalize-period (actual-outcome uint)))`

-   **Purpose:** Called by the `contract-owner` to close the current period, record the actual market outcome, and calculate the final aggregated sentiment.

-   **State Update:** Calculates the final sentiment, updates `period-sentiment` with the results, and increments `current-period`.

#### `(define-public (claim-rewards (period uint)))`

-   **Purpose:** Allows a user to claim their stake and any potential rewards for a finalized period.

-   **Reward Logic:** Calculates reward based on accuracy threshold (**u80**). Accurate predictions receive a bonus, while inaccurate ones receive a partial refund. It also calls `(update-user-reputation...)` to update the user's score.

* * * * *

🛠️ Usage and Deployment
------------------------

### Dependencies

This contract is written in **Clarity** and designed for the **Stacks blockchain**.

### Public Functions (Entrypoints)

| **Function** | **Parameters** | **Description** | **Permissions** |
| --- | --- | --- | --- |
| `submit-sentiment` | `(sentiment uint) (confidence uint)` | Submits a sentiment score and stakes collateral. | Any user |
| `finalize-period` | `(actual-outcome uint)` | Closes the current period and calculates the final result. | `contract-owner` only |
| `claim-rewards` | `(period uint)` | Claims stake/rewards for a specific, finalized period. | Any user (who submitted) |

### Read-Only Functions

These functions do not modify the blockchain state and are used for querying data.

-   `(get-current-period)`: Returns the ID of the current open period.

-   `(get-period-sentiment (period uint))`: Returns the aggregated data for a specific period.

-   `(get-user-submission (user principal) (period uint))`: Returns the details of a user's submission for a given period.

-   `(get-user-reputation (user principal))`: Returns the full reputation profile for a given user.

* * * * *

⚠️ Error Codes
--------------

| **Error Constant** | **Value** | **Description** |
| --- | --- | --- |
| `err-owner-only` | `u100` | Operation restricted to the contract owner. |
| `err-invalid-sentiment` | `u101` | Sentiment or actual outcome is outside the valid u1-u100 range. |
| `err-already-submitted` | `u102` | User has already submitted for the current period, or is attempting to claim a reward they already claimed. |
| `err-no-submission` | `u105` | No submission found for the given user/period. |
| `err-already-finalized` | `u106` | Attempted to finalize a period that is already closed. |
| `err-not-finalized` | `u107` | Attempted to claim rewards for a period that is not yet finalized. |

* * * * *

🤝 Contribution
---------------

I welcome contributions to SentinelOracle. If you've found a bug, have a suggestion for improvement, or wish to add new features, please follow these guidelines:

1.  **Fork** the repository.

2.  **Create a feature branch** (`git checkout -b feature/AmazingFeature`).

3.  **Commit** your changes (`git commit -m 'Add some AmazingFeature'`). Ensure your commit messages are clear and descriptive.

4.  **Push** to the branch (`git push origin feature/AmazingFeature`).

5.  **Open a Pull Request** (PR).

All contributions must adhere to the existing code style and structure. New features should be accompanied by relevant unit tests (if a Clarinet/testing environment is used).

* * * * *

⚖️ License
----------

This project is licensed under the **MIT License**.

```
MIT License

Copyright (c) 2025 SentinelOracle Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

* * * * *

🔮 Future Enhancements
----------------------

The following features are being considered for future versions:

-   **Dynamic Staking:** Allowing users to stake an amount greater than `min-stake-amount` to increase their base reward potential.

-   **Decentralized Finalization:** Implementing a mechanism (e.g., a simple majority vote or decentralized oracle integration) to allow the community or a set of authorized participants to input the `actual-outcome`, removing reliance on a single `contract-owner`.

-   **Governance Integration:** Allowing STX or project token holders to vote on changes to constants like `min-stake-amount` or `accuracy-threshold`.

* * * * *

📧 Contact
----------

For any questions or discussions regarding the SentinelOracle smart contract, please feel free to reach out to the project maintainers via the GitHub repository's Issues page.
