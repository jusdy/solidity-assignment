import hardhatRuntimeEnvironment, { ethers } from "hardhat";
import { ContractFactory, Signer } from "ethers";
import { FactoryOptions, HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployOptions } from "hardhat-deploy/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

type Modify<T, R> = Omit<T, keyof R> & R;
type DeployParam<T extends ContractFactory> = Parameters<InstanceType<{ new (): T }>["deploy"]>;
type ContractInstance<T extends ContractFactory> = ReturnType<InstanceType<{ new (): T }>["attach"]>;

export interface Accounts {
  [name: string]: SignerWithAddress;
}

class Ship {
  public accounts: Accounts;
  public users: SignerWithAddress[];
  public hre: HardhatRuntimeEnvironment;
  private log: boolean | undefined;

  constructor(hre: HardhatRuntimeEnvironment, accounts: Accounts, users: SignerWithAddress[], log?: boolean) {
    this.hre = hre;
    this.log = log;
    this.users = users;
    this.accounts = accounts;
  }

  static init = async (
    hre: HardhatRuntimeEnvironment = hardhatRuntimeEnvironment,
    log?: boolean,
  ): Promise<Ship> => {
    const namedAccounts = await hre.getNamedAccounts();
    const accounts: Accounts = {};
    const users: SignerWithAddress[] = [];
    for (const [name, address] of Object.entries(namedAccounts)) {
      const signer = await ethers.getSigner(address);
      accounts[name] = signer;
    }
    const unnammedAccounts = await hre.getUnnamedAccounts();
    for (const address of unnammedAccounts) {
      const signer = await ethers.getSigner(address);
      users.push(signer);
    }
    const ship = new Ship(hre, accounts, users, log);
    return ship;
  };

  get addresses(): string[] {
    const addresses: string[] = [];
    for (const [, user] of Object.entries(this.users)) {
      addresses.push(user.address);
    }
    return addresses;
  }

  get provider() {
    return this.hre.ethers.provider;
  }

  deploy = async <T extends ContractFactory>(
    contractFactory: new () => T,
    option?: Modify<
      DeployOptions,
      {
        from?: SignerWithAddress;
        args?: DeployParam<T>;
        log?: boolean;
        aliasName?: string | null;
      }
    >,
  ) => {
    const contractName = contractFactory.name.split("__")[0];

    const aliasName = option?.aliasName ?? contractName;

    const from = option?.from || this.accounts.deployer;
    const fromAddr = from.address;

    let log = option?.log || this.log;
    if (log === undefined) {
      if (this.hre.network.name !== "hardhat") {
        log = true;
      } else {
        log = false;
      }
    }

    const deployResult = await this.hre.deployments.deploy(aliasName, {
      ...option,
      contract: contractName,
      from: fromAddr,
      args: option?.args,
      log,
    });

    const contract = (await ethers.getContractAt(
      contractName,
      deployResult.address,
      from,
    )) as ContractInstance<T>;

    return {
      contract,
      ...deployResult,
    };
  };

  connect = async <T extends ContractFactory>(
    contractFactory: (new () => T) | string,
    newAddress?: string,
    signerOrOptions?: Signer | string | FactoryOptions,
  ): Promise<ContractInstance<T>> => {
    const contractName =
      typeof contractFactory == "string" ? contractFactory : contractFactory.name.split("__")[0];
    if (newAddress) {
      const factory = (await ethers.getContractFactory(
        contractName,
        signerOrOptions ?? this.accounts.deployer,
      )) as T;
      return factory.attach(newAddress) as ContractInstance<T>;
    } else {
      return (await ethers.getContract(contractName, this.accounts.deployer)) as ContractInstance<T>;
    }
  };
}

export default Ship;
