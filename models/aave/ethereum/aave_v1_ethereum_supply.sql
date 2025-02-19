{{ config(
    schema = 'aave_v1_ethereum'
    , alias='supply'
    , post_hook='{{ expose_spells(\'["ethereum"]\',
                                  "project",
                                  "aave_v1",
                                  \'["batwayne", "chuxin"]\') }}'
  )
}}

{% set aave_mock_address = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' %}
{% set weth_address = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' %}

SELECT 
      version,
      transaction_type,
      erc20.symbol,
      deposit.token as token_address, 
      depositor,
      withdrawn_to,
      liquidator,
      amount / concat('1e',erc20.decimals) AS amount,
      (amount / concat('1e',p.decimals)) * price AS usd_amount,
      evt_tx_hash,
      evt_index,
      evt_block_time,
      evt_block_number 
FROM (
 SELECT 
    '1' AS version,
    'deposit' AS transaction_type,
    CASE
        WHEN _reserve = '{{aave_mock_address}}' THEN '{{weth_address}}' --Using WETH instead of Aave "mock" address
        ELSE _reserve
    END AS token,
    _user AS depositor, 
    NULL::string AS withdrawn_to,
    NULL::string AS liquidator,
    _amount AS amount,
    evt_tx_hash,
    evt_index,
    evt_block_time,
    evt_block_number
FROM {{ source('aave_ethereum','LendingPool_evt_Deposit') }}
UNION ALL 
SELECT 
    '1' AS version,
    'withdraw' AS transaction_type,
    CASE
        WHEN _reserve = '{{aave_mock_address}}' THEN '{{weth_address}}' --Using WETH instead of Aave "mock" address
        ELSE _reserve
    END AS token,
    _user AS depositor,
    _user AS withdrawn_to,
    NULL::string AS liquidator,
    - _amount AS amount,
    evt_tx_hash,
    evt_index,
    evt_block_time,
    evt_block_number
FROM {{ source('aave_ethereum','LendingPool_evt_RedeemUnderlying') }}
UNION ALL 
SELECT 
    '1' AS version,
    'deposit_liquidation' AS transaction_type,
    CASE
        WHEN _reserve = '{{aave_mock_address}}' THEN '{{weth_address}}' --Using WETH instead of Aave "mock" address
        ELSE _collateral
    END AS token,
    _user AS depositor,
    _liquidator AS withdrawn_to,
    _liquidator AS liquidator,
    - _liquidatedCollateralAmount AS amount,
    evt_tx_hash,
    evt_index,
    evt_block_time,
    evt_block_number
FROM {{ source('aave_ethereum','LendingPool_evt_LiquidationCall') }}
) deposit
LEFT JOIN {{ ref('tokens_ethereum_erc20') }} erc20
    ON deposit.token = erc20.contract_address
LEFT JOIN {{ source('prices','usd') }} p 
    ON p.minute = date_trunc('minute', deposit.evt_block_time) 
    AND p.contract_address = deposit.token 
    AND p.blockchain = 'ethereum'
;