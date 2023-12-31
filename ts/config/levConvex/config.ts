import { StratType, genStratName, tokens } from '../utils';

export const addrs = {
  mainnet: {
    UniswapV3Router: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
    THREE_CRV: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
    GearDistributor: '0xA7Df60785e556d65292A2c9A077bb3A8fBF048BC',
    DegenDistributor: '0x6cA68adc7eC07a4bD97c97e8052510FBE6b67d10',
    DegenNFT: '0xB829a5b349b01fc71aFE46E50dD6Ec0222A6E599',
  },
};

const defaultRewardTokens = [
  tokens.mainnet.CRV,
  tokens.mainnet.CVX,
  tokens.mainnet.GEAR,
];

const type = StratType.LevCVX;

export const levConvex = [
  {
    name: genStratName(type, 'USDC', ['sUSD'], ['Gearbox'], 'mainnet'),
    type,
    curveAdapter: '0xbfB212e5D9F880bf93c47F3C32f6203fa4845222',
    // different adapter required to compute deposit amounts
    curveAdapterDeposit: '0x2bBDcc2425fa4df06676c4fb69Bd211b63314feA',
    convexRewardPool: '0xbEf6108D1F6B85c4c9AA3975e15904Bb3DFcA980',
    creditFacade: '0x61fbb350e39cc7bF22C01A469cf03085774184aa',
    convexBooster: '0xB548DaCb7e5d61BF47A026903904680564855B4E',
    coinId: 1, // curve token index of underlying
    underlying: tokens.mainnet.USDC,
    riskAsset: tokens.mainnet.sUSD,
    leverageFactor: 500,
    farmRouter: addrs.mainnet.UniswapV3Router,
    farmTokens: [...defaultRewardTokens],
    chain: 'mainnet',
  },
  {
    name: genStratName(type, 'USDC', ['FRAX'], ['Gearbox'], 'mainnet'),
    type,
    curveAdapter: '0xa4b2b3Dede9317fCbd9D78b8250ac44Bf23b64F4',
    convexRewardPool: '0x023e429Df8129F169f9756A4FBd885c18b05Ec2d',
    creditFacade: '0x61fbb350e39cc7bF22C01A469cf03085774184aa',
    convexBooster: '0xB548DaCb7e5d61BF47A026903904680564855B4E',
    coinId: 1, // curve token index
    underlying: tokens.mainnet.USDC,
    riskAsset: tokens.mainnet.FRAX,
    leverageFactor: 500,
    farmRouter: addrs.mainnet.UniswapV3Router,
    farmTokens: [...defaultRewardTokens],
    chain: 'mainnet',
  },
  {
    name: genStratName(type, 'USDC', ['gUSD', '3Crv'], ['Gearbox'], 'mainnet'),
    type,
    is3crv: true,
    curveAdapter: '0x6fA17Ffe020d72212A4DcA1560b27eA3cDAf965D',
    convexRewardPool: '0x3D4a70e5F355EAd0690213Ae9909f3Dc41236E3C',
    creditFacade: '0x61fbb350e39cc7bF22C01A469cf03085774184aa',
    convexBooster: '0xB548DaCb7e5d61BF47A026903904680564855B4E',
    underlying: tokens.mainnet.USDC,
    riskAsset: tokens.mainnet.gUSD,
    leverageFactor: 500,
    farmRouter: addrs.mainnet.UniswapV3Router,
    farmTokens: [...defaultRewardTokens],
    chain: 'mainnet',
  },

  {
    name: genStratName(type, 'USDC', ['lUSD', '3Crv'], ['Gearbox'], 'mainnet'),
    type,
    is3crv: true,
    curveAdapter: '0xD4c39a18338EA89B29965a8CAd28B7fb063c1429',
    convexRewardPool: '0xc34Ef7306B82f4e38E3fAB975034Ed0f76e0fdAA',
    creditFacade: '0x61fbb350e39cc7bF22C01A469cf03085774184aa',
    convexBooster: '0xB548DaCb7e5d61BF47A026903904680564855B4E',
    underlying: tokens.mainnet.USDC,
    riskAsset: tokens.mainnet.lUSD,
    leverageFactor: 500,
    farmRouter: addrs.mainnet.UniswapV3Router,
    farmTokens: [...defaultRewardTokens],
    chain: 'mainnet',
  },
  {
    name: genStratName(type, 'USDC', ['FRAX', '3Crv'], ['Gearbox'], 'mainnet'),
    type,
    is3crv: true,
    curveAdapter: '0x1C8281606377d79522515681BD94fc9d02b0d20B',
    convexRewardPool: '0xB26e063F062F76f9F7Dfa1a3f4b7fDa4A2197DfB',
    creditFacade: '0x61fbb350e39cc7bF22C01A469cf03085774184aa',
    convexBooster: '0xB548DaCb7e5d61BF47A026903904680564855B4E',
    underlying: tokens.mainnet.USDC,
    riskAsset: tokens.mainnet.FRAX,
    leverageFactor: 500,
    farmRouter: addrs.mainnet.UniswapV3Router,
    farmTokens: [...defaultRewardTokens],
    chain: 'mainnet',
  },
];
