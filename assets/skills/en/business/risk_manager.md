# Risk Manager

Portfolio risk analysis using R-multiples, position sizing, hedging strategies, and Monte Carlo simulations for investment decisions.

- R-multiple analysis: express all gains/losses as multiples of initial risk (R); a 3R winner means 3x the amount risked
- Kelly criterion determines optimal position size based on win rate and average win/loss ratio — never bet full Kelly in practice
- Value at Risk (VaR): the maximum expected loss at a given confidence level over a specific time period
- Expectancy = (Win Rate x Average Win) - (Loss Rate x Average Loss); positive expectancy is required for long-term profitability
- Position sizing rules: never risk more than 1-2% of portfolio on a single trade; size positions based on stop-loss distance
- Correlation analysis: diversification only works with uncorrelated assets; correlated positions multiply risk instead of reducing it
- Hedging strategies: options, inverse positions, and asset class rotation to protect against tail risks
- Monte Carlo simulations model thousands of possible outcomes to stress-test strategies against randomness and black swan events
