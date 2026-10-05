-- Shop Websites, on the Bank since FoxyOS 14.1, ahead of the Pockets that
-- open them in 15. A store's address on the web is name.shop. Every other
-- domain is one word with no dot, so no website can ever be called this:
-- the Bank keeps the .shop names itself, one store each, and anybody may
-- ask which store is at one.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local function as(who, action, extra)
    extra = extra or {}
    extra.app_id = "COMPANY"
    return bank.request(action, bank.as(who, extra))
end
local fox = as(ana, "COMPANY_CREATE", { company_name = "Foxy Shopping" }).company
local wolf = as(kit, "COMPANY_CREATE", { company_name = "Wolf Wares" }).company
-- Something on sale in each, which a store needs before it can open.
for _, pair in ipairs({ { ana, fox }, { kit, wolf } }) do
    local who, company = pair[1], pair[2]
    as(who, "COMPANY_PRODUCT_ADD", { company_id = company.company_id, name = "Lamp",
        price = 12, kind = "one_time" })
    as(who, "COMPANY_PRODUCT_SET", { company_id = company.company_id,
        item_id = bank.state.companies[company.company_id].quick_items[1].item_id,
        online = true })
end

-- Only an open store, and only its owner ---------------------------------------------

rejected(as, "STORE_CLOSED", ana, "COMPANY_SHOP_SITE",
    { company_id = fox.company_id, site = "foxyshopping" })
as(ana, "COMPANY_SHOP_SETUP", { company_id = fox.company_id, open = true })
as(kit, "COMPANY_SHOP_SETUP", { company_id = wolf.company_id, open = true })
rejected(as, "NOT_OWNER", kit, "COMPANY_SHOP_SITE",
    { company_id = fox.company_id, site = "mine" })
rejected(bank.request, "WRONG_APP", "COMPANY_SHOP_SITE", bank.as(ana,
    { app_id = "SHOP", company_id = fox.company_id, site = "foxyshopping" }))

-- The address -------------------------------------------------------------------------

for _, bad in ipairs({ "ab", "has space", "-dash", "dash-", "dot.dot",
    "twentyonecharacterss1" }) do
    rejected(as, "BAD_DOMAIN", ana, "COMPANY_SHOP_SITE",
        { company_id = fox.company_id, site = bad })
end
-- Typed with capitals and the ending, as people will.
local made = as(ana, "COMPANY_SHOP_SITE", { company_id = fox.company_id,
    site = "FoxyShopping.shop" }).shop_site
assert(made.domain == "foxyshopping.shop", "lower case, ending once: " .. made.domain)
assert(as(ana, "COMPANY_STATE", { company_id = fox.company_id }).shop_site.domain
    == "foxyshopping.shop", "the Company app sees it")
-- One store each.
rejected(as, "SITE_TAKEN", kit, "COMPANY_SHOP_SITE",
    { company_id = wolf.company_id, site = "foxyshopping" })
-- The same store may say it again, and change it.
assert(as(ana, "COMPANY_SHOP_SITE", { company_id = fox.company_id,
    site = "foxyshopping" }).shop_site.revision == 2)

-- Looking one up: anybody, no account -------------------------------------------------

local found = bank.request("SHOP_SITE", { domain = "FOXYSHOPPING.shop" })
assert(found.company_id == fox.company_id and found.company_name == "Foxy Shopping"
    and found.open == true and found.domain == "foxyshopping.shop",
    "the store at the address")
assert(bank.request("SHOP_SITE", { domain = "foxyshopping" }).company_id
    == fox.company_id, "with or without the ending")
assert(bank.request("SHOP_SITE", { company_id = fox.company_id }).domain
    == "foxyshopping.shop", "and from the store, for a Pocket replacing its Shop App")
rejected(bank.request, "NO_SUCH_SITE", "SHOP_SITE", { domain = "nobody.shop" })
rejected(bank.request, "NO_SUCH_SITE", "SHOP_SITE", { company_id = wolf.company_id })
rejected(bank.request, "BAD_DOMAIN", "SHOP_SITE", { domain = "x" })
-- On the storefront too.
local store = bank.request("SHOP_STORE", bank.as(kit, { company_id = fox.company_id }))
assert((store.store or store).site == "foxyshopping.shop", "the storefront names its address")

-- A closed store keeps its address and says it is closed.
as(ana, "COMPANY_SHOP_SETUP", { company_id = fox.company_id, open = false })
assert(bank.request("SHOP_SITE", { domain = "foxyshopping.shop" }).open == false)
as(ana, "COMPANY_SHOP_SETUP", { company_id = fox.company_id, open = true })

-- Renamed, the old address is free for somebody else.
as(ana, "COMPANY_SHOP_SITE", { company_id = fox.company_id, site = "foxy" })
rejected(bank.request, "NO_SUCH_SITE", "SHOP_SITE", { domain = "foxyshopping.shop" })
assert(as(kit, "COMPANY_SHOP_SITE", { company_id = wolf.company_id,
    site = "foxyshopping" }).shop_site.domain == "foxyshopping.shop")

-- Taken down.
as(ana, "COMPANY_SHOP_SITE", { company_id = fox.company_id, enabled = false })
rejected(bank.request, "NO_SUCH_SITE", "SHOP_SITE", { domain = "foxy.shop" })
assert(as(ana, "COMPANY_STATE", { company_id = fox.company_id }).shop_site == nil)

print("host_shop_site_test: OK")
