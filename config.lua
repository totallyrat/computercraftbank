-- PUMPE Ecosystem v6 configuration.
-- Copy this file with the rest of the project to each ComputerCraft computer.

return {
    version = "9.3.0",
    protocol = "PUMPE_BANK_V5",
    hostname = "BANK_SERVER",

    -- Every bank on the network, Foxy and third-party alike, speaks this one
    -- protocol for settling between them. It is deliberately separate from
    -- the banking protocol above: a transfer between two banks must not
    -- queue behind everyday banking, and a third-party bank has no business
    -- on Foxy's own channel.
    ledger_protocol = "PUMPE_LEDGER_V1",
    -- A third-party bank's own protocol. Its clients are the Bank App on
    -- each PUMPE, and nothing else on the network speaks it.
    tpb_protocol = "PUMPE_TPB_V1",

    -- ComputerCraftGaming runs on its own computer since 9.1. The Bank keeps
    -- the Bet Wallet and the money in play; this is where the games are.
    ccg_protocol = "PUMPE_CCG_V1",
    ccg_hostname = "CCG_SERVER",
    -- How long the Bank holds a wager for a lobby before giving it back on
    -- its own. It only has to outlast a game, so a CCG Server that is
    -- switched off mid-round cannot strand anybody's money.
    ccg_escrow_hours = 2,

    -- Proximity pay at a third-party bank: how far away a charge can be
    -- picked up, and how long one waits before it lapses.
    tpb_charge_range = 12,
    tpb_charge_ttl_ms = 3 * 60 * 1000,
    -- Foxy is bank 0001. A third-party bank picks its own four digits when
    -- its server is set up, and hosts LEDGER_<code> under the protocol above.
    foxy_bank_code = "0001",
    bank_name = "Foxy",

    -- Pair Mode. Two Bank Servers split the work: the Core keeps banking on
    -- the hot path, the Vault takes the update depot and app records off it.
    pair_protocol = "PUMPE_PAIR_V1",
    pair_hostname = "BANK_VAULT",
    pair_code_seconds = 600,
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

    -- Proximity Pay, ticket scanning and visa checks. Devices report where
    -- they are, and a kiosk, door or border asks the nearest PUMPE with a
    -- recent fix. present_max_age_ms is how long a ticket or travel document
    -- counts as "held up" after the screen showing it last checked in.
    proximity_pay_radius = 16,
    present_max_age_ms = 20 * 1000,
    proximity_offer_ttl_ms = 60 * 1000,
    position_max_age_ms = 90 * 1000,
    gps_report_seconds = 20,

    -- How often a signed-in PUMPE checks whether a friend is reaching it
    -- through Urgent Contact. This runs from whatever app is open.
    urgent_ring_poll_seconds = 3,
    smart_declare_fee = 150,
    lifetime_smart_declare_fee = 5000,

    -- The starting key for the Bank Admin Terminal. Change it from inside the
    -- terminal itself; the live key lives in the Bank database, not here.
    government_key = "Government1234",

    -- Settings a release takes back. A device still carrying the value on the
    -- right gets the new default instead, because an update otherwise
    -- preserves every local setting and a retired placeholder would stay
    -- forever.
    config_resets = { government_key = "CHANGE-ME-GOVERNMENT-KEY" },

    -- Foxy. The new bank inside the PUMPE: sub-accounts you can split money
    -- into, and Foxy Cash, an instant friends-only transfer with a flat fee
    -- and no daily ceiling. BuckApp keeps working through the migration.
    foxy_cash_fee_rate = 0.02,
    max_pots_per_account = 8,

    -- The App Server. Optional apps are downloaded from here rather than
    -- from the Bank, so a busy download never slows banking down. Publishing
    -- is the only thing that touches the Bank, and only to check the
    -- developer is real.
    -- What an installed app is allowed to keep on the Bank. Records are
    -- small on purpose: an app store is not a place to put a database.
    max_app_records = 200,
    max_app_record_bytes = 400,
    max_app_reactions = 60,

    -- What an app is allowed to do to your attention. The alert budget is
    -- per sender, per app, per in-game day: generous for a chat app and
    -- useless for a spammer. The PIN lockout defends the Pin API against
    -- the app holding it rather than against a person.
    max_app_collections = 40,
    -- In-app purchases. The government's share of everything an app sells,
    -- taken by the Bank rather than trusted to the app or the seller.
    app_purchase_tax_rate = 0.30,
    max_app_purchase = 5000,
    max_app_notifications_per_day = 60,
    pin_check_lockout_seconds = 120,

    app_protocol = "PUMPE_APPS_V1",
    app_hostname = "APP_SERVER",
    app_chunk_size = 6000,
    max_app_bytes = 96 * 1024,
    max_apps_installed = 12,

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
