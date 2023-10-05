import { deployments } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { Ship, advanceTimeAndBlock, getTime } from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  MockERC20,
  MockERC20__factory,
  ProviderControllerBonus,
  ProviderControllerBonus__factory,
} from "../types";
import { solidityKeccak256 } from "ethers/lib/utils";

chai.use(solidity);
const { expect } = chai;

let ship: Ship;
let token: MockERC20;
let providerController: ProviderControllerBonus;

let deployer: SignerWithAddress;
let signer: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;

const setup = deployments.createFixture(async (hre) => {
  ship = await Ship.init(hre);
  const { accounts, users } = ship;
  await deployments.fixture(["provider-controller-bonus"]);

  return {
    ship,
    accounts,
    users,
  };
});

describe("ProviderControllerBonus test", () => {
  before(async () => {
    const { accounts } = await setup();

    deployer = accounts.deployer;
    signer = accounts.signer;
    alice = accounts.alice;
    bob = accounts.bob;

    token = await ship.connect(MockERC20__factory);
    providerController = await ship.connect(ProviderControllerBonus__factory);
  });

  it("register provider", async () => {
    // reverts when fee is small
    const registerKey = solidityKeccak256(["string"], ["Provider 0"]);
    let fee = 200_000_000_000n; // 200 gwei
    await expect(providerController.connect(alice).registerProvider(registerKey, fee)).to.revertedWith(
      "ProviderController: fee is too small",
    );

    fee = 250_000_000_000n; // 250 gwei
    await expect(providerController.connect(alice).registerProvider(registerKey, fee))
      .to.emit(providerController, "ProviderAdded")
      .withArgs(1, alice.address, registerKey, fee);

    const providerData = await providerController.providers(1);

    expect(providerData.owner).eq(alice.address);
    expect(providerData.subscriberCount).eq(0);
    expect(providerData.fee).eq(fee);
    expect(providerData.balance).eq(0);
    expect(providerData.active).eq(true);
  });

  it("can't register again with same register key", async () => {
    const registerKey = solidityKeccak256(["string"], ["Provider 0"]);
    const fee = 250_000_000_000n;
    await expect(providerController.connect(alice).registerProvider(registerKey, fee)).to.revertedWith(
      "ProviderController: register key already used",
    );
  });

  it("can register more than 200", async () => {
    for (let i = 1; i < 201; i++) {
      const registerKey = solidityKeccak256(["string"], [`Provider ${i}`]);
      const fee = 250_000_000_000n;
      await providerController.connect(alice).registerProvider(registerKey, fee);
    }
  });

  it("update provider state", async () => {
    await expect(providerController.connect(alice).updateProvidersState([1, 2], [true])).to.revertedWith(
      "Ownable: caller is not the owner",
    );

    await expect(providerController.updateProvidersState([1, 2], [true])).to.revertedWith(
      "ProviderController: invalid param",
    );

    await expect(providerController.updateProvidersState([1], [false]))
      .to.emit(providerController, "ProviderStateChanged")
      .withArgs(1, false);

    const providerData = await providerController.providers(1);
    expect(providerData.active).eq(false);

    await providerController.connect(alice).removeProvider(2);
    await expect(providerController.updateProvidersState([2], [true])).to.revertedWith(
      "ProviderController: provider not registered",
    );
  });

  it("register subscriber", async () => {
    let deposit = 5_000_000_000_000n; // insufficient deposit
    await expect(providerController.connect(bob).registerSubscriber(deposit, "test", [1, 2])).to.revertedWith(
      "ProviderController: invalid param",
    );
    await expect(
      providerController
        .connect(bob)
        .registerSubscriber(deposit, "test", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
    ).to.revertedWith("ProviderController: invalid param");

    await expect(
      providerController.connect(bob).registerSubscriber(deposit, "test", [1, 2, 3]),
    ).to.revertedWith("ProviderController: provider is inactive"); // provider 1 is inactive now

    await expect(
      providerController.connect(bob).registerSubscriber(deposit, "test", [2, 3, 4]),
    ).to.revertedWith("ProviderController: provider is removed"); // provider 2 is not exist

    await expect(
      providerController.connect(bob).registerSubscriber(deposit, "test", [3, 4, 5]),
    ).to.revertedWith("ProviderController: deposit amount is too small");

    deposit = 6_000_000_000_000n; // insufficient deposit
    await expect(
      providerController.connect(bob).registerSubscriber(deposit, "test", [3, 4, 5]),
    ).to.revertedWith("ERC20: insufficient allowance");

    await token.connect(bob).mint(deposit);
    await token.connect(bob).approve(providerController.address, deposit);

    await expect(providerController.connect(bob).registerSubscriber(deposit, "test", [3, 4, 5]))
      .to.emit(providerController, "SubscriberAdded")
      .withArgs(1, bob.address, "test", deposit)
      .to.emit(token, "Transfer")
      .withArgs(bob.address, providerController.address, deposit);

    const providerData = await providerController.providers(3);
    const subscriberData = await providerController.subscribers(1);

    expect(providerData.subscriberCount).eq(1);
    expect(subscriberData.owner).eq(bob.address);
    expect(subscriberData.balance).eq(deposit);
    expect(subscriberData.plan).eq("test");
    expect(subscriberData.paused).eq(false);
  });

  it("pause subscribe", async () => {
    await expect(providerController.connect(alice).pauseSubscription(1)).to.revertedWith(
      "ProviderController: permission denied",
    );

    await providerController.connect(bob).pauseSubscription(1);
    const subscriberData = await providerController.subscribers(1);
    expect(subscriberData.paused).eq(true);
  });

  it("deposit", async () => {
    const deposit = 6_000_000_000_000n;
    await expect(providerController.connect(alice).deposit(1, deposit)).to.revertedWith(
      "ProviderController: permission denied",
    );
    await expect(providerController.connect(bob).deposit(1, deposit)).to.revertedWith(
      "ProviderController: paused subscription",
    );

    await token.connect(bob).mint(2n * deposit);
    await token.connect(bob).approve(providerController.address, 2n * deposit);
    await providerController.connect(bob).registerSubscriber(deposit, "test", [3, 4, 5]);

    let subscriberData = await providerController.subscribers(2);
    expect(subscriberData.balance).eq(deposit);

    await expect(providerController.connect(bob).deposit(2, deposit))
      .to.emit(token, "Transfer")
      .withArgs(bob.address, providerController.address, deposit);

    subscriberData = await providerController.subscribers(2);
    expect(subscriberData.balance).eq(2n * deposit);
  });

  it("withdraw provider earning", async () => {
    advanceTimeAndBlock(8 * 7 * 24 * 60 * 60); // 8 weeks
    await expect(providerController.connect(bob).withdrawProviderEarnings(1)).to.revertedWith(
      "ProviderController: permission denied",
    );
    await expect(providerController.connect(alice).withdrawProviderEarnings(1)).to.revertedWith(
      "ProviderController: provider is inactive",
    );
    await expect(providerController.connect(alice).withdrawProviderEarnings(2)).to.revertedWith(
      "ProviderController: provider is removed",
    );

    await expect(providerController.connect(alice).withdrawProviderEarnings(3))
      .to.emit(token, "Transfer")
      .withArgs(providerController.address, alice.address, 2_000_000_000_000n);

    const subscriberData = await providerController.subscribers(2);
    expect(subscriberData.balance).eq(10_000_000_000_000n); // 12000 - 2000 = 10000 (gwei)
  });

  it("remove provider", async () => {
    await expect(providerController.connect(bob).removeProvider(1)).to.revertedWith(
      "ProviderController: permission denied",
    );
    await expect(providerController.connect(alice).removeProvider(1)).to.revertedWith(
      "ProviderController: provider is inactive",
    );
    await expect(providerController.connect(alice).removeProvider(2)).to.revertedWith(
      "ProviderController: provider is already removed",
    );
    await expect(providerController.connect(alice).removeProvider(3))
      .to.emit(providerController, "ProviderRemoved")
      .withArgs(3);
  });

  it("test view functions", async () => {
    expect(await providerController.getProviderEarning(4)).to.eq(2_000_000_000_000n); // 8 weeks with 250 gwei
    expect(await providerController.getSubscriberRemaining(2)).to.eq(6_000_000_000_000n); // 8 weeks with 250 gwei for three providers
  });

  it("update provider fee", async () => {
    await expect(providerController.connect(bob).updateProvideFee(1, 200_000_000_000n)).to.revertedWith(
      "ProviderController: fee is too small",
    );
    await expect(providerController.connect(bob).updateProvideFee(1, 300_000_000_000n)).to.revertedWith(
      "ProviderController: permission denied",
    );
    await expect(providerController.connect(alice).updateProvideFee(1, 300_000_000_000n)).to.revertedWith(
      "ProviderController: provider is inactive",
    );
    await expect(providerController.connect(alice).updateProvideFee(2, 300_000_000_000n)).to.revertedWith(
      "ProviderController: provider is already removed",
    );
    await expect(providerController.connect(alice).updateProvideFee(4, 300_000_000_000n))
      .to.emit(providerController, "ProviderFeeUpdated")
      .withArgs(4, 300_000_000_000n);

    const providerData = await providerController.providers(4);
    expect(providerData.balance).eq(2_000_000_000_000n);
    expect(providerData.fee).eq(300_000_000_000n);
  });
});
