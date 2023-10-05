// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProviderController (Solidity Assignment)
 * @dev scaled bonus requirements
 */
contract ProviderControllerBonus is Ownable {
  /// @dev token which uses for payment
  IERC20 public immutable token;

  struct Provider {
    uint32 subscriberCount;
    uint256 fee; // fee is the cost in token units that the provider charges to subscribers per month
    address owner;
    uint256 balance; // the provider balance is stored in the contract
    bool active;
  }

  struct Subscriber {
    address owner;
    uint256 balance; // the subscriber balance is stored in the contract
    string plan; // basic / premium / vip
    bool paused;
  }

  /// @dev minimum fee (for example our minimum fee is 1000 gwei)
  uint256 public constant MIN_FEE = 250 gwei;
  /// @dev fee calculation period (in this case, period is a month)
  uint256 public constant FEE_CALCULATION_PERIOD = 7 days;
  /// @dev min deposit period (in this case, two months)
  uint256 public constant MIN_DEPOSIT_PERIOD = 8;

  /// @dev counter ids
  uint64 private providerId;
  uint64 private subscriberId;

  /// @dev providers (providerId => Provider)
  mapping(uint64 => Provider) public providers;
  /// @dev subscribers (subscriberId => Subscriver)
  mapping(uint64 => Subscriber) public subscribers;

  /// @dev subscriber ids which subscribed to provider (providerId => [subscriberId])
  mapping(uint64 => uint64[]) private providerSubscribers;
  /**
   * @dev saves subscriber id index(uppper) in providerSubscribers
   *     if subscribers count is bigger, we need to retrieve all to get subscriber id,
   *     but if we add this param, can get index from subscriberId and subscriberId from index
   *     (subscriberId => providerId => upperIndex)
   */
  mapping(uint64 => mapping(uint64 => uint256)) private subscribeUpperIndex;
  /// @dev provider ids of subscriber (subscriberId => [providerId])
  mapping(uint64 => uint64[]) private subscriberProviders;
  /// @dev provider index in providers of subscriber
  mapping(uint64 => mapping(uint64 => uint256)) private providerUpperIndex;
  /// @dev saves register key usage
  mapping(bytes32 => bool) private registerKeyUsage;
  /// @dev saves subscribed time (providerId => subscriberId => timestamp)
  mapping(uint64 => mapping(uint64 => uint256)) private subscribedTime;

  // Events
  event ProviderAdded(
    uint64 indexed providerId,
    address indexed owner,
    bytes publicKey,
    uint256 fee
  );
  event ProviderStateChanged(uint64 indexed providerId, bool state);
  event ProviderRemoved(uint64 indexed providerId);
  event ProviderFeeUpdated(uint64 indexed providerId, uint256 fee);

  event SubscriberAdded(
    uint64 indexed subscriberId,
    address indexed owner,
    string plan,
    uint256 deposit
  );

  constructor(address _token) {
    token = IERC20(_token);
  }

  /**
   * @notice register new provider
   * @param _registerKey register key
   * @param _fee fee os provider
   */
  function registerProvider(
    bytes calldata _registerKey,
    uint256 _fee
  ) external returns (uint64 id) {
    // fee (token units) should be greater than a fixed value. Add a check
    require(_fee >= MIN_FEE, "ProviderController: fee is too small");

    // the system doesn't allow to register a provider with the same registerKey.
    // Implement a way to prevent it.
    bytes32 registerKeyHash = keccak256(abi.encodePacked(_registerKey));
    require(
      registerKeyUsage[registerKeyHash] == false,
      "ProviderController: register key already used"
    );
    registerKeyUsage[registerKeyHash] = true;

    id = ++providerId;
    providers[id] = Provider({
      owner: msg.sender,
      balance: 0,
      subscriberCount: 0,
      fee: _fee,
      active: true
    });

    emit ProviderAdded(id, msg.sender, _registerKey, _fee);
  }

  /**
   * @notice remove provider with provider id
   * @param _providerId id of provider
   */
  function removeProvider(uint64 _providerId) external {
    // Only the owner of the Provider can remove it
    require(providers[_providerId].owner == _msgSender(), "ProviderController: permission denied");
    require(providers[_providerId].active, "ProviderController: provider is inactive");
    require(providers[_providerId].fee > 0, "ProviderController: provider is already removed");

    // improve gas cost
    uint256 currentBalance = providers[_providerId].balance;

    Provider memory provider = providers[_providerId];

    provider.balance = 0;
    provider.subscriberCount = 0;
    provider.fee = 0;

    providers[_providerId] = provider;

    if (currentBalance > 0) {
      transferBalance(msg.sender, currentBalance);
    }

    emit ProviderRemoved(_providerId);
  }

  /**
   * @notice updates provider fee with provider id
   * @param _providerId id of provider
   * @param _fee fee to update
   */
  function updateProvideFee(uint64 _providerId, uint256 _fee) external {
    require(_fee >= MIN_FEE, "ProviderController: fee is too small");
    require(providers[_providerId].owner == _msgSender(), "ProviderController: permission denied");
    require(providers[_providerId].active, "ProviderController: provider is inactive");
    require(providers[_providerId].fee > 0, "ProviderController: provider is already removed");

    // get earnings so far with past fee
    uint256 earnings = calculateProviderEarnings(_providerId);
    Provider memory provider = providers[_providerId];
    provider.balance += earnings;
    provider.fee = _fee;

    providers[_providerId] = provider;

    emit ProviderFeeUpdated(_providerId, _fee);
  }

  /**
   * @notice update provider state (owner can call this function)
   * @param _providerIds id list of providers
   * @param _states states to change
   */
  function updateProvidersState(
    uint64[] calldata _providerIds,
    bool[] calldata _states
  ) external onlyOwner {
    require(_providerIds.length == _states.length, "ProviderController: invalid param");

    // Implement the logic of this function
    // It will receive a list of provider Ids and a flag (enable /disable)
    // and update the providers state accordingly (active / inactive)
    // You can change data structures if that helps improve gas cost
    // Remember the limt of providers in the system is 200
    // Only the owner of the contract can call this function
    for (uint256 i = 0; i < _providerIds.length; i++) {
      require(providers[_providerIds[i]].fee != 0, "ProviderController: provider not registered");
      providers[_providerIds[i]].active = _states[i];

      emit ProviderStateChanged(_providerIds[i], _states[i]);
    }
  }

  /**
   * @notice register new subscriber
   * @param _deposit deposit fee amount
   * @param _plan plan to subscribe (just string param)
   * @param _providerIds id list of providers to subscribe
   */
  function registerSubscriber(
    uint256 _deposit,
    string memory _plan,
    uint64[] calldata _providerIds
  ) external {
    // Provider list must at least 3 and less or equals 14
    require(
      _providerIds.length > 2 && _providerIds.length < 15,
      "ProviderController: invalid param"
    );
    // plan does not affect the cost of the subscription

    uint64 id = ++subscriberId;

    uint256 totalFee = 0;
    for (uint256 i = 0; i < _providerIds.length; i++) {
      // Only allow subscriber registrations if providers are active
      require(
        providers[_providerIds[i]].owner != address(0),
        "ProviderController: provider is not registered"
      );
      require(providers[_providerIds[i]].fee > 0, "ProviderController: provider is removed");
      require(providers[_providerIds[i]].active, "ProviderController: provider is inactive");
      require(
        subscribeUpperIndex[id][_providerIds[i]] == 0,
        "ProviderController: already subscribed"
      );

      // increase provider subscriber count
      providers[_providerIds[i]].subscriberCount++;
      // add subscriber id to provider subscribes
      providerSubscribers[_providerIds[i]].push(id);
      // saves index of subscribe to save fee
      subscribeUpperIndex[id][_providerIds[i]] = providerSubscribers[_providerIds[i]].length;
      // saves index of provider
      providerUpperIndex[_providerIds[i]][id] = i + 1;
      // set subscribe start time
      subscribedTime[_providerIds[i]][id] = block.timestamp;

      totalFee += providers[_providerIds[i]].fee * MIN_DEPOSIT_PERIOD;
    }
    // save provider id list of subscriber
    subscriberProviders[id] = _providerIds;

    // check if the deposit amount cover expenses of providers' fees for at least 2 months
    require(totalFee <= _deposit, "ProviderController: deposit amount is too small");
    subscribers[id] = Subscriber({
      owner: msg.sender,
      balance: _deposit,
      plan: _plan,
      paused: false
    });

    // deposit the funds
    token.transferFrom(msg.sender, address(this), _deposit);

    emit SubscriberAdded(id, msg.sender, _plan, _deposit);
  }

  /**
   * @notice pause all subscription of subscribe and pause subscriber
   * @param _subscriberId id of subscriber
   */
  function pauseSubscription(uint64 _subscriberId) external {
    // Only the subscriber owner can pause the subscription
    require(
      msg.sender == subscribers[_subscriberId].owner,
      "ProviderController: permission denied"
    );
    subscribers[_subscriberId].paused = true;

    // when the subscription is paused, it must be removed from providers list (providerSubscribers)
    // and for every provider, reduce subscriberCount

    // when pausing a subscription, the funds of the subscriber are not transferred back to the owner

    for (uint64 i = 0; i < subscriberProviders[_subscriberId].length; i++) {
      if (subscribeUpperIndex[_subscriberId][subscriberProviders[_subscriberId][i]] == 0) {
        continue;
      }

      // updates subscription balance
      uint256 index = subscribeUpperIndex[_subscriberId][subscriberProviders[_subscriberId][i]] - 1;
      (uint256 earning, ) = calculateSubscriptionEarning(
        subscriberProviders[_subscriberId][i],
        _subscriberId
      );
      // cancel subscription
      cancelSubscribe(subscriberProviders[_subscriberId][i], index);
      subscribeUpperIndex[_subscriberId][subscriberProviders[_subscriberId][i]] = 0;

      providers[subscriberProviders[_subscriberId][i]].balance += earning;
    }
  }

  /**
   * @notice deposit more fee to subscriber
   * @param _subscriberId id of subscriber
   * @param _deposit deposit amount
   */
  function deposit(uint64 _subscriberId, uint256 _deposit) external {
    // Only the subscriber owner can deposit to the subscription
    require(
      msg.sender == subscribers[_subscriberId].owner,
      "ProviderController: permission denied"
    );
    require(!subscribers[_subscriberId].paused, "ProviderController: paused subscription");

    token.transferFrom(msg.sender, address(this), _deposit);
    subscribers[_subscriberId].balance += _deposit;
  }

  /**
   * @notice withdraw provider earning
   * @param _providerId id of provider
   */
  function withdrawProviderEarnings(uint64 _providerId) public {
    // only the owner of the provider can withdraw funds
    require(providers[_providerId].owner == _msgSender(), "ProviderController: permission denied");
    require(providers[_providerId].active, "ProviderController: provider is inactive");
    require(providers[_providerId].fee > 0, "ProviderController: provider is removed");

    // IMPORTANT: before withdrawing, the amount eraned from subscribers needs to be calculated
    uint256 amount = calculateProviderEarnings(_providerId);

    transferBalance(msg.sender, amount);
  }

  // view functions
  /**
   * @notice get provider earning
   * @param _providerId id of provider
   */
  function getProviderEarning(uint64 _providerId) external view returns (uint256 earnings) {
    // Calculate the earnings for a given provider based on subscribers count and provider fee
    // The calculation is made on a full month basis.
    for (uint256 i = 0; i < providerSubscribers[_providerId].length; ++i) {
      // get earning of subscription
      uint256 earning = getSubscriptionEarning(_providerId, providerSubscribers[_providerId][i]);
      earnings += earning;
    }

    earnings += providers[_providerId].balance;
  }

  /**
   * @notice get subscription remaining
   * @param _subscriberId id of subscriber
   */
  function getSubscriberRemaining(uint64 _subscriberId) external view returns (int256 remaining) {
    uint256 totalUsed = 0;
    for (uint64 i = 0; i < subscriberProviders[_subscriberId].length; i++) {
      if (subscribeUpperIndex[_subscriberId][subscriberProviders[_subscriberId][i]] == 0) {
        continue;
      }

      // get spendin of subscription
      uint256 earning = getSubscriptionEarning(
        subscriberProviders[_subscriberId][i],
        _subscriberId
      );
      totalUsed += earning;
    }

    if (totalUsed <= subscribers[_subscriberId].balance) {
      remaining = int(subscribers[_subscriberId].balance - totalUsed);
    } else {
      remaining = -1 * int(totalUsed - subscribers[_subscriberId].balance);
    }
  }

  // private functions
  /// @dev calcualte provider earning and updates subscription state
  function calculateProviderEarnings(uint64 _providerId) private returns (uint256 earnings) {
    // Calculate the earnings for a given provider based on subscribers count and provider fee
    // The calculation is made on a full month basis.
    for (uint256 i = 0; i < providerSubscribers[_providerId].length; ++i) {
      // get earning of subscritpion
      (uint256 earning, bool isInsufficient) = calculateSubscriptionEarning(
        _providerId,
        providerSubscribers[_providerId][i]
      );
      if (isInsufficient) {
        // if run out of fee, removes subscription
        cancelSubscribe(_providerId, i);
        subscribeUpperIndex[providerSubscribers[_providerId][i]][_providerId] = 0;
      }

      earnings += earning;
    }

    earnings += providers[_providerId].balance;

    providers[_providerId].balance = 0;
  }

  /// @dev calculate earning of subscription
  function calculateSubscriptionEarning(
    uint64 _providerId,
    uint64 _subscriberId
  ) private returns (uint256 earning, bool isInsufficient) {
    uint256 amount = (block.timestamp - subscribedTime[_providerId][_subscriberId]) /
      FEE_CALCULATION_PERIOD;
    earning = amount * providers[_providerId].fee;
    // Updates subscription time
    subscribedTime[_providerId][_subscriberId] += FEE_CALCULATION_PERIOD * amount;
    // Updates subscriber state
    if (subscribers[_subscriberId].balance < earning) {
      earning = subscribers[_subscriberId].balance;
      subscribers[_subscriberId].balance = 0;

      isInsufficient = true;
    } else {
      subscribers[_subscriberId].balance -= earning;
      isInsufficient = false;
    }
  }

  /// @dev get subscription earning
  function getSubscriptionEarning(
    uint64 _providerId,
    uint64 _subscriberId
  ) private view returns (uint256 earning) {
    uint256 amount = (block.timestamp - subscribedTime[_providerId][_subscriberId]) /
      FEE_CALCULATION_PERIOD;
    earning = amount * providers[_providerId].fee;
    // Updates subscription time
    // Updates subscriber state
    if (subscribers[_subscriberId].balance < earning) {
      earning = subscribers[_subscriberId].balance;
    }
  }

  /// @dev cancel subscribe
  function cancelSubscribe(uint64 _providerId, uint256 _index) private {
    uint64[] memory providerSubscriber = new uint64[](providerSubscribers[_providerId].length - 1);
    uint256 i = 0;

    uint64 _subscriberId = providerSubscribers[_providerId][_index];
    uint256 providerIndex = providerUpperIndex[_providerId][_subscriberId];
    while (providerIndex < subscriberProviders[_providerId].length) {
      providerIndex++;
      subscriberProviders[_subscriberId][providerIndex - 1] = subscriberProviders[_subscriberId][
        providerIndex
      ];
      providerUpperIndex[subscriberProviders[_subscriberId][providerIndex - 1]][_subscriberId]--;
    }

    // updates subscriber list of provider
    while (i < providerSubscribers[_providerId].length) {
      if (i > _index) {
        providerSubscriber[i - 1] = providerSubscribers[_providerId][i];
        subscribeUpperIndex[providerSubscriber[i - 1]][_providerId] = i;
      } else if (i < _index) {
        providerSubscriber[i] = providerSubscribers[_providerId][i];
      }

      ++i;
    }
    providerSubscribers[_providerId] = providerSubscriber;

    // decrease subscriber count of provider
    providers[_providerId].subscriberCount -= 1;
  }

  /// @dev transfers token
  function transferBalance(address to, uint256 amount) private {
    token.transfer(to, amount);
  }

  function revokeRemaining(uint256 amount) external onlyOwner {
    token.transfer(msg.sender, amount);
  }
}
