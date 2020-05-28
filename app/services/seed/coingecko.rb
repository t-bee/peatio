# frozen_string_literal: true

module Seed
  class Coingecko < Base
    SUPPORTED_BASE_CURRENCIES = %w[aed ars aud bch bdt bhd bmd bnb brl btc cad chf
                                   clp cny czk dkk eos eth eur gbp hkd huf idr ils
                                   inr jpy krw kwd lkr ltc mmk mxn myr nok nzd php
                                   pkr pln rub sar sek sgd thb try twd uah usd vef
                                   vnd xag xau xdr xlm xrp zar].freeze

    COINGECKO_INFO_PARAMS = {
      localization: 'false',
      tickers: false,
      market_data: true,
      community_data: false,
      developer_data: false,
      sparkline: false
    }.freeze

    # FOR Gas Price we can use "gastracker" or "gasoracle"
    # Etherscan.default_client.get(module: "gastracker", action: "gasestimate", gasprice: "1000000000") => "145" (result in seconds)
    # Etherscan.default_client.get(module: "gastracker", action: "gasoracle") => {:LastBlock=>"10135184", :SafeGasPrice=>"35", :ProposeGasPrice=>"46"} (in GWEI)
    # Or
    # Etherscan.default_client.get(module: "proxy", action: "eth_GasPrice") => Etherscan::APIError: {:jsonrpc=>"2.0", :id=>73, :result=>"0x737be7600"}

    def check_base_currency
      if SUPPORTED_BASE_CURRENCIES.exclude? base_currency
        raise StandardError, 'Unsupported base currency for Coingecko'
      end
    end

    def coingecko_client
      @coingecko_client ||= ::Coingecko::Client.new
    end

    def etherscan_client
      settings = {
        api_key: @settings.dig(:etherscan, :api_key),
        network: @settings.dig(:etherscan, :network)
      }

      @etherscan_client ||= ::Etherscan::Client.new(settings)
    end

    def filters
      @filters ||= @settings[:filters]
    end

    def blockchains
      @blockchains ||= @settings[:blockchain_mapping]
    end

    def tarrifs
      @tarrifs ||= @settings[:tarrifs]
    end

    # TODO: Rate limiting, Logger info, improve adapter logic
    def prefetch_currencies
      check_base_currency
      seeds = []
      @position = 0
      global_info = coingecko_client.get('/search', locale: 'en')
      whitelisted_coins = global_info[:coins].select { |coin| coin[:id].in? filters[:coingecko_ids] }
      filtered_coins = global_info[:coins].select { |coin| coin[:market_cap_rank].present? && coin[:market_cap_rank] <= filters[:market_cap_rank] && whitelisted_coins.exclude?(coin) }

      whitelisted_coins.each do |coin|
        token_info = coingecko_client.get("/coins/#{coin[:id]}", COINGECKO_INFO_PARAMS)
        seeds << form_payload(token_info)
      rescue ::Faraday::Error => e
        Rails.logger.info "Error happened to #{coin[:id]} coin"
        Rails.logger.error e
        next
      end

      filtered_coins.each do |coin|
        token_info = coingecko_client.get("/coins/#{coin[:id]}", COINGECKO_INFO_PARAMS)
        if token_info[:asset_platform_id].in? filters[:asset_platform_ids]
          seeds << form_payload(token_info)
        end
      rescue ::Faraday::Error => e
        Rails.logger.info "Error happened to #{coin[:id]} coin"
        Rails.logger.error e
        next
      end

      File.open( output_file, 'w') { |f| f.write seeds.each(&:deep_stringify_keys!).to_yaml }
    end

    def precision(current_price)
      raw_precision = Math.log(current_price * 100, 10)
      raw_precision <= 0 ? 0 : raw_precision.ceil + 1
    end

    def form_payload(info)
      current_price = info.dig(:market_data, :current_price, base_currency.to_sym).to_d
      @position += 1

      currency = {
        id: info[:symbol],
        name: info[:name],
        blockchain_key: blockchains.fetch(info[:asset_platform_id]&.to_sym, "CHANGEME"),
        symbol: "CHANGEME",
        type: 'coin',
        deposit_fee: tarrifs[:deposit_fee] / current_price.to_f,
        min_deposit_amount: tarrifs[:min_deposit_amount] / current_price.to_f,
        min_collection_amount: tarrifs[:min_collection_amount] / current_price.to_f,
        withdraw_fee: tarrifs[:withdraw_fee] / current_price.to_f,
        min_withdraw_amount: tarrifs[:min_withdraw_amount] / current_price.to_f,
        withdraw_limit_24h: tarrifs[:withdraw_limit_24h] / current_price.to_f,
        withdraw_limit_72h: tarrifs[:withdraw_limit_72h] / current_price.to_f,
        position: @position,
        visible: true,
        deposit_enabled: true,
        withdrawal_enabled: true,
        icon_url: info.dig(:image, :small),
        precision: precision(current_price)
      }


      case info[:asset_platform_id]
      when 'ethereum'
        etherscan_data = etherscan_contract_info(info[:contract_address])
        {
            base_factor: 10**etherscan_data[:tokenDecimal].to_i,
            options: {
                gas_amount: 21_000,
                gas_price: 1_000_000_000,
                erc20_contract_address: info[:contract_address],
                coingecko_id: info[:id],
                base_currency: base_currency,
                price: current_price.to_f
            }
        }.yield_self { |p| currency.merge!(p) }

      else
        Rails.logger.info "For #{info[:id]} you need to check config and replace 'CHANGEME' fields"
        {
            base_factor: "CHANGEME",
            options: {
                coingecko_id: info[:id],
                base_currency: base_currency,
                price: current_price.to_f
            }
        }.yield_self { |p| currency.merge!(p) }
      end
    end

    def etherscan_contract_info(contract_address)
      result = etherscan_client.get(module: 'account',
                                    action: 'tokentx',
                                    page: 1,
                                    offset: 1,
                                    contractaddress: contract_address)
      result.first
    rescue ::Faraday::Error => e
      Rails.logger.error e
    rescue ::Etherscan::Client::APIError => e
      Rails.logger.error "Error happened to contract_address #{contract_address} "
      Rails.logger.warn e
    end
  end
end
