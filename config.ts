import BigNumber from 'bignumber.js'
BigNumber.config({ EXPONENTIAL_AT: 60 })

// использовать разный env для разных сетей - абсолютно не удобно, я предлагаю использовать ts файл для хранения всех параметров для деплоя, тк это безопаснее, удобнее и быстрее

const DLD_INITIAL_SUPPLY = 1000000 * 10**18; // 1_000_000 tokens(with 18 decimals)

export default {
	DLD_NAME: 'DLD Token',
	DLD_SYMBOL: 'DLD',
	DLD_INITIAL_SUPPLY: DLD_INITIAL_SUPPLY.toString(), 

	DLS_NAME: 'DLS Token',
	DLS_SYMBOL: 'DLS',

	REWARDS_PER_EPOCH: new BigNumber('100').shiftedBy(18).toString(),
	START_TIME: '0',
	EPOCH_DURATION: new BigNumber(60 * 60 * 24).toString(),
	HALVING_DURATION: new BigNumber(60 * 60 * 24 * 3).toString(),
	FINE_DURATION: new BigNumber(60 * 2).toString(),
	FINE_PERCENTAGE: new BigNumber(0.2).shiftedBy(20).toString(),

	VESTING_UNLOCK_1: '',
	VESTING_UNLOCK_2: '',
	VESTING_PERIOD: new BigNumber(60 * 60 * 24 * 5).toString(),
	VESTING_PERCENT: new BigNumber(0.88).shiftedBy(20).toString(),

	// map к каждой сети
	'bsc_testnet': {
		DLD_ADDRESS: '0x25eF370518F625153F7cFAD7cde97A4d4a2eE888',
		DLS_ADDRESS: '0x48573C722920B615E57945D202a605A7bDf42bEf',

		BRIDGE: '0x7aaFdfA09cC67F2f18C9C388cc0678266b9601F6',
		VESTING: '0xC667Fa12E89b031BD52ECC872C2E5997BB124F7C',

		STAKE: '0xB248B4BBf0Bb9c78c79002599047Ca938346AE6a',
		FARM: '0xA23Ba9f445F6f81feAe1F48269e0168556a94822',
	},

	rinkeby: {
		DLD_ADDRESS: '0xDC2DE46a65d91963d1315f4F19CCCB00844d97ef',
		DLS_ADDRESS: '0xff439FFE8E23618917f8Aaa1e4909aF331aF7995',

		BRIDGE: '0x6a5a89cF39fACdaA8d43Af443753D73537fAeFd5',
	}
} as { [keys: string]: any}
