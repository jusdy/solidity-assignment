## Solidity Assignment

## Requirements

### Assignment Instructions

The contract you are working on is a Provider-Subscriber system. It models a marketplace where entities, referred to as "Providers", can offer some services for a monthly fee. These services are consumed by entities known as "Subscribers". The Providers and Subscribers interact with each other using a specific ERC20 token as the medium of payment. Both Providers and Subscribers have their balances maintained within the contract.

The contract maintains a registry of Providers and Subscribers, identified by their respective IDs. Each Provider has its list of Subscribers. A Subscribed should use a certain number of Providers. Additionally, a Provider can be in one of two states: active or inactive, depending on whether it can currently provide services or not. A subscription can be paused, so the Subscriber is not charged by Providers.

### Key Functionalities

**Provider Registration**: Providers can register themselves by specifying a registration key and a fee. The system prevents a Provider from registering more than once using the same key. There is also a maximum limit on the number of Providers that can be registered (200).

**Provider Removal**: Providers can be removed from the system, but only by their respective owners. The balance held in the contract is returned to the owner upon removal.
Subscriber Registration: Subscribers can register with one or more active Providers.
They deposit a certain amount into the contract, which should cover at least two months' worth of provider fees. The plan chosen by the subscriber does not affect the cost of the subscription.

**Subscription Pause**: Subscribers can pause their subscription. When a subscription is paused, the subscriber is removed from the provider's list, and its active status is set to false.

**Increase the subscription deposit**: Subscribers can increase the balance of subscriptions by transferring funds to the contract.

**Withdraw Provider Earnings**: Providers can withdraw their earnings from the contract, which are calculated based on their subscriber count and the fees they charge. The calculation is made every month.

**Update Provider State**: The state of the Providers (active or inactive) can be updated.
Only the contract owner can call this function.

**View functions**: Read-only functions are a key part of this system. Implement these:
- Get the state of a provider by id: returns number of subscribers, fee, owner,
balance, and state.
- Get the provider earnings by id.
- Get the state of a subscriber by id: owner, balance, plan, and state.
- Get the live balance of a subscriber (its deposit balance minus the expected fees that will be charged by providers)

## Bonus Section
Here are some additional questions that delve deeper into the contract's functionality and its potential improvements:

**Balance Management**: Currently, the contract operates monthly, meaning that subscribers need to deposit at least two months' worth of fees when they register. Could this process be improved or made more precise? Consider whether allowing subscribers to pay for services on a daily or even hourly basis would be more efficient. How could such a feature be implemented?

**System Scalability**: The current system restricts the maximum number of providers to 200. How could this system be changed to become more scalable and remove such a limitation? Are there changes to the data structures or other modifications that would allow the system to handle a theoretically unlimited number of providers?

**Changing Provider Fees**: Currently, providers set their fees upon registration. What if
a provider needs to change their fee after registration? How can the system ensure
that the correct amount is charged to subscribers, mainly if the fee change occurs
partway through a billing cycle? Consider how such a feature could be implemented
while maintaining fairness for both providers and subscribers.


## Setting up local development

### Pre-requisites

- [Node.js](https://nodejs.org/en/) version 14.0+ and [yarn](https://yarnpkg.com/) for Javascript environment.
- [Foundry](https://github.com/gakonst/foundry#installation) for running forge tests.

1. Clone this repository

```bash
git clone ...
```

2. Install dependencies

```bash
yarn
```

3. Set environment variables on the .env file according to .env.example

```bash
cp .env.example .env
vim .env
```

4. Compile Solidity programs

```bash
yarn compile
```

### Development

- To run hardhat tests

```bash
yarn test
```


- To start local blockchain

```bash
yarn localnode
```

- To run scripts on Sepolia test

```bash
yarn script:sepolia ./scripts/....
```

- To run deploy contracts on Sepolia testnet (uses Hardhat deploy)

```bash
yarn deploy:sepolia --tags ....
```

- To verify contracts on etherscan

```bash
yarn verify:sepolia ProviderController
```

... see more useful commands in package.json file

## Main Dependencies

Contracts are developed using well-known open-source software for utility libraries and developement tools. You can read more about each of them.

[OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)

[Hardhat](https://github.com/nomiclabs/hardhat)

[hardhat-deploy](https://github.com/wighawag/hardhat-deploy)

[ethers.js](https://github.com/ethers-io/ethers.js/)

[TypeChain](https://github.com/dethcrypto/TypeChain)
