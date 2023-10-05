import { DeployFunction } from "hardhat-deploy/types";
import { MockERC20__factory, ProviderControllerBonus__factory } from "../types";
import { Ship } from "../utils";

const func: DeployFunction = async (hre) => {
  const { deploy } = await Ship.init(hre);

  let tokenContract = "0x00";
  if (hre.network.tags.test) {
    const token = await deploy(MockERC20__factory);

    tokenContract = token.address;
  }

  await deploy(ProviderControllerBonus__factory, {
    args: [tokenContract],
  });
};

export default func;
func.tags = ["provider-controller-bonus"];
