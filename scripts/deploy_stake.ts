import config from '../config'
import { ethers, network } from 'hardhat'
import { Staking } from '../typechain'

const {
	REWARDS_PER_EPOCH,
	EPOCH_DURATION,
	HALVING_DURATION,
	FINE_DURATION,
	FINE_PERCENTAGE,
	START_TIME
} = config

async function main() {

	// let startTime = START_TIME;
	let startTime = Math.round(Date.now() / 1000) + 60;
	console.log('startTime', startTime)

	const { DLS_ADDRESS, DLD_ADDRESS } = config[network.name]

	const Staking = await ethers.getContractFactory('Staking')
	const staking = await Staking.deploy(
		REWARDS_PER_EPOCH,
		startTime,
		EPOCH_DURATION,
		HALVING_DURATION,
		FINE_DURATION,
		FINE_PERCENTAGE,
		DLD_ADDRESS,
		DLS_ADDRESS
	) as Staking

	console.log(`staking has been deployed to: ${staking.address}`);
}

main()
.then(() => process.exit(0))
.catch(error => {
	console.error(error);
	process.exit(1);
});
