# Stable Earn

1. Stable Earn is a fund for you to invest BUSD and earn stable yield in BUSD at almost zero risk.

Under the hood, it buys BNB to stake on Stader (ultimately used for BNB POS staking) and hedges the BNB price fluctuations with a perp position on Deri Protocol. This fund enables you to earn BUSD from BNB staking rewards without worrying about BNB price fluctuations.

1. How Stable Earn works?
Stable Earn runs a BNB POS staking fund, with its purpose to help users earn BNB staking yield with their BUSD investment. 90% of the BUSD invested will be swapped into BNB which is staked to Stader for POS yield. That is, 90% of the capital is participating in the Proof-of-Staking of the BNB Smart Chain (BSC). The rest 10% will be used as margin on Deri Protocol to short BNB perps. This combination ensures that the net value of the fund is not affected by BNB price fluctuations. 

1. What are the fees？
Stable Earn does not charge any fees. 
However, when users invest or redeem, they will incur transaction fees, including fees for BNB-BUSD swapping and trading BNB perps. These fees are charged for the use of these platform services and are not controlled by Stable Earn.

1. What is FLP?
FLP (short for Fund LP) is an ERC20 token that represents your ownership of the fund's assets. When you invest in Stable Earn, the fund will issue you a certain number of FLP tokens based on the NAV of the fund at the time of investment. When you redeem, the FLP tokens will be locked and the estimated redemption BUSD amount will be calculated based on the number of FLP tokens * the NAV of the fund at the time of redemption. When the redemption is completed, the FLP tokens will be burned.

1. What is the redemption process?
As with all BNB staking platforms, there is a 15-day unbound period to fully redeem your investment. You need to initiate a redemption request first and the FLP token in your wallet will be locked in the fund contract. Your investment will not accrue yield once the redemption process starts. The requested funds will be available for withdrawal in 15 days.
Alternatively, you can use Instant Redeem, which will convert BNBX to BNB in DEX and then swap into BUSD for withdrawal. Please note, however, that as BNB/BNBX generally has a discounted rate on DEX, Instant Redeem will leave you with a little less withdrawable funds compared to the regular redemption process.

1. What are the risks?
Liquidation risk: If the BNB price rises significantly, the corresponding short position may be at risk of liquidation. The keeper will actively monitor the margin account at all times. When the margin falls below a certain limit, the keeper will manually trigger a rebalance transaction: sell part of the BNBX and restore the margin to the expected level. But we can not exclude the possibility of liquidation under extreme market conditions. 

Smart contract risk: The underlying smart contracts of Deri Protocol and Stader have been audited by Peckshield and Certik. but there’s always the possibility of a bug or vulnerability compromising participants' funds.

1. How is Projected APY calculated?
The Stable Earn helps users to earn yield from BNB staking. The projected APY(7.92%) is calculated as BNB staking yield (8.8%) * 0.9, where the 0.9 coef. refers 90% of the investment in BUSD converted to BNB staking. However, please note that this is only the projected APY and the actual APY may vary.

	


