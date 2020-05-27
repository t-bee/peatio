class PrefillService
  SUPPORTED_ASSETS = %w[ardor ark atom ada btc bch dash eos eth neo ltc miota mkr xem xmr xlm xrp zec zrx].freeze

  # FOR Gas Price we can use "gastracker" or "gasoracle"
  # Etherscan.default_client.get(module: "gastracker", action: "gasestimate", gasprice: "1000000000") => "145" (result in seconds)
  # Etherscan.default_client.get(module: "gastracker", action: "gasoracle") => {:LastBlock=>"10135184", :SafeGasPrice=>"35", :ProposeGasPrice=>"46"} (in GWEI)
  # Or
  # Etherscan.default_client.get(module: "proxy", action: "eth_GasPrice") => Etherscan::APIError: {:jsonrpc=>"2.0", :id=>73, :result=>"0x737be7600"}

  GLOBAL_SETTINGS = {
      number_of_tokens: 500
  }
  COIN_INFO_PARAMS = {
      localization:   "false",
      tickers:        false,
      market_data:    true,
      community_data: true,
      developer_data: true,
      sparkline:      true
  }.freeze

  def coingecko_client
    @coingecko_client ||= Coingecko.default_client
  end

  def etherscan_client
    @etherscan_client ||= Etherscan.default_client
  end

  def coingecko_get_all_coins
    coingecko_client.get("/coins/list")
  end

  def coingecko_get_top_coins(path, params)
    coingecko_client.get(path, params)
  end

  def coingecko_get_info(path, params)
    coingecko_client.get(path, params)
  end

  def etherscan_contract_info(contract_address)
    result = etherscan_client.get(module:          "account",
                                  action:          "tokentx",
                                  page:            1,
                                  offset:          1,
                                  contractaddress: contract_address)
    result.first
  rescue ::Faraday::Error => e
    Rails.logger.error e
  rescue ::Etherscan::APIError => e
    Rails.logger.error "Error happened to contract_address #{contract_address} "
    Rails.logger.warn e
  end

  def perform
    # 1. Get all coins from Coingecko
    # 2. Curl all of them and from payload

    all_coins = coingecko_get_top_coins("/search", locale: "en")
    top_500 = all_coins.fetch(:coins).select { |coin| coin[:market_cap_rank].present? && coin[:market_cap_rank] <= GLOBAL_SETTINGS[:number_of_tokens] }
    prefill_payload = {
        erc20: [],
        supported_by_platform: [],
        strange_contracts: [],
        unsupported: []
    }
    top_500.each do |coin|
      Rails.logger.info "Processing #{coin}"
      sleep 20 if coin[:market_cap_rank] % 10 == 0
      response = coingecko_get_info("/coins/#{coin[:id]}", COIN_INFO_PARAMS)
      File.open("spec/resources/#{coin[:id]}.json", "w") { |f| f.write(response) }
      result = form_payload(response)
      prefill_payload[result[:category]] << result[:payload]
    end
    File.open("spec/resources/result.yml", "w") { |f| f.write prefill_payload.to_yaml }
    prefill_payload
  end

  def form_payload(info)
    current_price_in_usd = info.dig(:market_data, :current_price, :usd).to_d
    raw_precision = Math.log(current_price_in_usd * 100, 10)
    precision = if raw_precision <= 0
                  0
                else
                  raw_precision.ceil + 1
                end
    if info[:asset_platform_id] == "ethereum"
      etherscan_data = etherscan_contract_info(info[:contract_address])
      if etherscan_data.present? && etherscan_data[:status] == 429
        return {payload: {code: info[:symbol], status: 429}, category: :erc20}
      end
      payload = {
          code:           info[:symbol],
          prefill_id:     info[:name],
          coingecko_id:   info[:id],
          name:           info[:name],
          blockchain_key: "eth-mainnet",
          rate:           current_price_in_usd.to_f,
          symbol:         info[:symbol], ##
          type:           "coin",
          base_factor:    10**etherscan_data[:tokenDecimal].to_i,
          precision:      precision,
          icon_url:       info.dig(:image, :small),
          options:        {
              gas_amount:             21_000,
              gas_price:              1_000_000_000,
              erc20_contract_address: info[:contract_address]
          }
      }
      return {payload: payload, category: :erc20}
    elsif info[:contract_address].present?
      etherscan_data = etherscan_contract_info(info[:contract_address])
      payload = {
          code:           info[:symbol],
          prefill_id:     info[:name],
          coingecko_id:   info[:id],
          name:           info[:name],
          blockchain_key: "eth-mainnet",
          rate:           current_price_in_usd.to_f,
          symbol:         info[:symbol], ##
          type:           "coin",
          base_factor:    "check info",
          precision:      precision,
          icon_url:       info.dig(:image, :small),
          options:        {
              gas_amount:             21_000,
              gas_price:              1_000_000_000,
              erc20_contract_address: info[:contract_address]
          }
      }
      return {payload: payload, category: :strange_contracts}

    elsif info[:symbol].in? SUPPORTED_ASSETS
      payload = {
          code:           info[:symbol],
          prefill_id:     info[:name],
          coinegcko_id:   info[:id],
          name:           info[:name],
          blockchain_key: "#{info[:symbol]}-mainnet",
          rate:           current_price_in_usd.to_f,
          symbol:         info[:symbol], ##
          type:           "coin",
          base_factor:    nil,
          precision:      precision,
          icon_url:       info.dig(:image, :small),
          options:        {}
      }
      return {payload: payload, category: :supported_by_platform}
    else
      payload = {
          code:           info[:symbol],
          prefill_id:     info[:name],
          coinegcko_id:   info[:id],
          name:           info[:name],
          blockchain_key: "#{info[:symbol]}-mainnet",
          rate:           current_price_in_usd.to_f,
          symbol:         info[:symbol], ##
          type:           "coin",
          base_factor:    nil,
          precision:      precision,
          icon_url:       info.dig(:image, :small),
          options:        {}
      }
      return {payload: payload, category: :unsupported}
    end
  end
end
