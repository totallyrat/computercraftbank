


return {
version = "16.5.2",



release_name = "FoxyOS 17 Beta 3",
protocol = "PUMPE_BANK_V5",



shop_confirm_hours = 2,
shop_min_return_days = 5,
shop_max_return_days = 30,
hostname = "BANK_SERVER",






ledger_protocol = "PUMPE_LEDGER_V1",


tpb_protocol = "PUMPE_TPB_V1",



ccg_protocol = "PUMPE_CCG_V1",
ccg_hostname = "CCG_SERVER",



ccg_escrow_hours = 2,



tpb_charge_range = 12,
tpb_charge_ttl_ms = 3 * 60 * 1000,


foxy_bank_code = "0001",
bank_name = "Foxy",



pair_protocol = "PUMPE_PAIR_V1",
pair_hostname = "BANK_VAULT",
pair_code_seconds = 600,
data_file = "bank_data_v5.dat",

currency = "$",
starting_balance = 500,
payment_code_ttl_ms = 5 * 60 * 1000,
session_ttl_ms = 12 * 60 * 60 * 1000,
max_ticket_quantity = 5,



ticket_turn_ms = 2 * 60 * 1000,
ticket_queue_shoppers = 3,
ticket_queue_stale_ms = 30 * 1000,
max_territories_per_account = 3,
visa_min_days = 1,
visa_max_days = 30,
permanent_visa_cooldown_seconds = 30,



bet_access_ttl_ms = 15 * 60 * 1000,
bet_hold_ingame_hours = 24,
bet_minimum = 1,
bet_maximum = 10000,



ccg_casino_credit = 10000,
ccg_lobby_ttl_ms = 5 * 60 * 1000,
ccg_result_delay_ms = 6 * 1000,
ccg_survivor_max_seconds = 75,



ccg_auto_start_seconds = 15,
ccg_auto_next_seconds = 8,

pin_free_limit = 50,
daily_spend_limit = 5000,
send_money_daily_limit = 2000,
send_money_fee_rate = 0.10,
pumpe_lock_seconds = 60,
pumpe_pin_seconds = 120,





proximity_pay_radius = 16,
present_max_age_ms = 20 * 1000,
proximity_offer_ttl_ms = 60 * 1000,
position_max_age_ms = 90 * 1000,
gps_report_seconds = 20,



urgent_ring_poll_seconds = 3,
smart_declare_fee = 150,
lifetime_smart_declare_fee = 5000,



government_key = "Government1234",





config_resets = { government_key = "CHANGE-ME-GOVERNMENT-KEY" },




foxy_cash_fee_rate = 0.02,
max_pots_per_account = 8,



subscription_periods = { 1, 2, 5, 10, 15 },






cloud_protocol = "PUMPE_CLOUD_V1",
cloud_free_bytes = 100 * 1024,
cloud_plus_bytes = 500 * 1024,
foxycloud_plus_price = 500,
foxycloud_plus_days = 5,



cloud_chunk_size = 6000,
cloud_copies = 1,
cloud_max_files = 100,


cloud_server_reserve_bytes = 20000,
cloud_server_seen_ms = 60 * 1000,
cloud_ticket_ms = 2 * 60 * 1000,







max_app_records = 200,
max_app_record_bytes = 400,
max_app_reactions = 60,





max_app_collections = 40,


app_purchase_tax_rate = 0.30,
max_app_purchase = 5000,
max_app_notifications_per_day = 60,
pin_check_lockout_seconds = 120,






web_protocol = "PUMPE_WEB_V1",
web_hostname = "INTERNET_SERVER",




max_web_bytes = 8 * 1024,
max_web_sites = 200,

app_protocol = "PUMPE_APPS_V1",
app_hostname = "APP_SERVER",
app_chunk_size = 6000,
max_app_bytes = 96 * 1024,
max_apps_installed = 12,


clock_source = "ingame",


auto_update = true,
update_manifest_url = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/release_manifest.json",
update_channel = "stable",



beta_manifest_url = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/beta/release_manifest.json",



update_check_seconds = 5,
client_update_check_seconds = 30,
}
