-- PUMPE Ecosystem v5 configuration.
-- Copy this file with the rest of the project to each ComputerCraft computer.

return {
    version = "5.2.1",
    protocol = "PUMPE_BANK_V5",
    hostname = "BANK_SERVER",
    data_file = "bank_data_v5.dat",

    currency = "$",
    starting_balance = 500,
    payment_code_ttl_ms = 5 * 60 * 1000,
    session_ttl_ms = 12 * 60 * 60 * 1000,
    gps_ttl_ms = 90 * 1000,
    proximity_update_seconds = 2,
    max_ticket_quantity = 5,

    pin_free_limit = 50,
    daily_spend_limit = 5000,
    send_money_daily_limit = 2000,
    send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60,
    pumpe_pin_seconds = 120,
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
    update_check_seconds = 10,
}
