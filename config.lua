-- PUMPE Ecosystem v6 configuration.
-- Copy this file with the rest of the project to each ComputerCraft computer.

return {
    version = "7.0.1",
    protocol = "PUMPE_BANK_V5",
    hostname = "BANK_SERVER",
    data_file = "bank_data_v5.dat",

    currency = "$",
    starting_balance = 500,
    payment_code_ttl_ms = 5 * 60 * 1000,
    session_ttl_ms = 12 * 60 * 60 * 1000,
    max_ticket_quantity = 5,
    max_territories_per_account = 3,
    visa_min_days = 1,
    visa_max_days = 30,
    permanent_visa_cooldown_seconds = 30,

    -- ComputerCraftGaming uses PUMPE game currency only. Winnings stay in a
    -- separate Bet Wallet and unlock after one complete in-game day.
    bet_access_ttl_ms = 15 * 60 * 1000,
    bet_hold_ingame_hours = 24,
    bet_minimum = 1,
    bet_maximum = 10000,
    ccg_lobby_ttl_ms = 5 * 60 * 1000,
    ccg_result_delay_ms = 6 * 1000,
    ccg_survivor_max_seconds = 75,

    -- CCG Auto Mode. The console keeps opening the next lobby on its own and
    -- only stops when the code entered at start-up is typed back in.
    ccg_auto_start_seconds = 15,
    ccg_auto_next_seconds = 8,

    pin_free_limit = 50,
    daily_spend_limit = 5000,
    send_money_daily_limit = 2000,
    send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60,
    pumpe_pin_seconds = 120,

    -- Proximity Pay. Devices report where they are, and the kiosk offers the
    -- bill to the nearest PUMPE that has a recent fix.
    proximity_pay_radius = 16,
    proximity_offer_ttl_ms = 60 * 1000,
    position_max_age_ms = 90 * 1000,
    gps_report_seconds = 20,

    -- How often a signed-in PUMPE checks whether a friend is reaching it
    -- through Urgent Contact. This runs from whatever app is open.
    urgent_ring_poll_seconds = 3,
    smart_declare_fee = 150,
    lifetime_smart_declare_fee = 5000,

    -- Change this before using the tax controller on a real server.
    government_key = "CHANGE-ME-GOVERNMENT-KEY",

    -- All event dates use the Minecraft/ComputerCraft in-game day.
    clock_source = "ingame",

    -- Stable public release manifest. Bank Servers poll this URL for updates.
    auto_update = true,
    update_manifest_url = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/release_manifest.json",
    update_channel = "stable",

    -- Only the Bank Server polls the internet. Clients ask the Bank for its
    -- version over the connection they already hold, so this can stay slow.
    update_check_seconds = 5,
    client_update_check_seconds = 30,
}
