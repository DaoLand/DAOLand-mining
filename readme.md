```sh
npm install
```

#### to deploy in bsc_testnet execute 
```sh
npm run deploy_stake_bsc_testnet
```

#### revert messages for Staking.sol 
|abbreviation|description|
|:---:|:---|
|"S:afz"|"Staking: accumulated fine is zero"|
|"S:sna"|"Staking: stake is not available now"|
|"S:stn"|"Staking: stake time has not come yet"|
|"S:una"|"Staking: unstake is not available now"|
|"S:netu"|"Staking: not enough tokens to unstake"|
|"S:ahr"|"Staking: you already have request with greater or equal amount"|
|"S:cna"|"Staking: claim is not available now"|
|"S:nc"|"Staking: nothing to claim"|
