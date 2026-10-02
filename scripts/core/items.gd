class_name Items
## Static item catalogue. Prices are in silver coins (12 silver = 1 gold).

const SILVER_PER_GOLD := 12

const DB := {
	# --- food -------------------------------------------------------------
	"bread": {"name": "Loaf of Bread", "type": "food", "value": 3, "hunger": 25, "desc": "A crusty loaf, still faintly warm."},
	"apple": {"name": "Apple", "type": "food", "value": 1, "hunger": 9, "thirst": 4, "desc": "Crisp and tart."},
	"cheese": {"name": "Wheel of Cheese", "type": "food", "value": 5, "hunger": 22, "desc": "Sharp, aged cheese."},
	"carrot": {"name": "Carrot", "type": "food", "value": 1, "hunger": 6, "desc": "Fresh from the field."},
	"dates": {"name": "Sweet Dates", "type": "food", "value": 3, "hunger": 12, "thirst": 2, "desc": "Sticky desert dates from the oasis groves."},
	"raw_meat": {"name": "Raw Venison", "type": "food", "value": 3, "hunger": 6, "cookable": "cooked_meat", "desc": "Cook it over a fire before eating."},
	"cooked_meat": {"name": "Roast Venison", "type": "food", "value": 7, "hunger": 42, "warmth": 4, "desc": "Juicy, fire-roasted meat."},
	"raw_fish": {"name": "Raw Fish", "type": "food", "value": 2, "hunger": 5, "cookable": "cooked_fish", "desc": "Best cooked over a fire."},
	"cooked_fish": {"name": "Grilled Fish", "type": "food", "value": 5, "hunger": 30, "desc": "Flaky and smoky."},
	"stew": {"name": "Hearty Stew", "type": "food", "value": 8, "hunger": 50, "warmth": 15, "desc": "Thick stew that warms the bones."},
	"honey_cake": {"name": "Honey Cake", "type": "food", "value": 14, "hunger": 35, "stamina": 30, "desc": "A rare treat sold on market days."},
	# --- drink ------------------------------------------------------------
	"waterskin": {"name": "Waterskin", "type": "drink", "value": 6, "thirst": 30, "charges": 5, "desc": "Refill it at any river, lake or well."},
	"ale": {"name": "Tankard of Ale", "type": "drink", "value": 2, "thirst": 18, "warmth": 3, "desc": "Frothy tavern ale."},
	"wine": {"name": "Bottle of Wine", "type": "drink", "value": 9, "thirst": 20, "desc": "Red wine from the southern vineyards."},
	"spiced_wine": {"name": "Spiced Wine", "type": "drink", "value": 18, "thirst": 22, "warmth": 25, "desc": "Mulled wine with eastern spices. Market day only."},
	"milk": {"name": "Jug of Milk", "type": "drink", "value": 2, "thirst": 22, "hunger": 5, "desc": "Fresh from the village cows."},
	# --- materials ------------------------------------------------------------
	"wolf_pelt": {"name": "Wolf Pelt", "type": "material", "value": 14, "desc": "Thick grey fur. Tanners pay well."},
	"bear_pelt": {"name": "Bear Pelt", "type": "material", "value": 36, "desc": "A massive pelt prized by northern furriers."},
	"deer_hide": {"name": "Deer Hide", "type": "material", "value": 9, "desc": "Supple hide for leatherwork."},
	"fox_pelt": {"name": "Fox Pelt", "type": "material", "value": 10, "desc": "A russet pelt."},
	"moose_antlers": {"name": "Moose Antlers", "type": "material", "value": 24, "desc": "Broad antlers - a hunter's trophy."},
	"feathers": {"name": "Bundle of Feathers", "type": "material", "value": 3, "desc": "Fletchers buy these."},
	"sealed_parcel": {"name": "Sealed Parcel", "type": "quest", "value": 0, "desc": "Wax-sealed and addressed in a merchant's hand. Not yours to open."},
	"firewood": {"name": "Firewood", "type": "material", "value": 1, "desc": "Dry split logs."},
	# --- weapons ----------------------------------------------------------------
	"rusty_sword": {"name": "Rusty Sword", "type": "weapon", "value": 30, "damage": 12, "desc": "Notched and pitted, but it still cuts."},
	"iron_sword": {"name": "Iron Sword", "type": "weapon", "value": 70, "damage": 19, "desc": "A dependable blade from a village smithy."},
	"steel_longsword": {"name": "Steel Longsword", "type": "weapon", "value": 140, "damage": 27, "desc": "Well balanced steel."},
	"knight_sword": {"name": "Knight's Estoc", "type": "weapon", "value": 240, "damage": 33, "desc": "A thrusting sword favoured by the knights of Aldmere."},
	"elven_blade": {"name": "Moonsilver Blade", "type": "weapon", "value": 420, "damage": 42, "rare": true, "desc": "Ancient and impossibly light. Only seen on market days."},
	# --- shields -----------------------------------------------------------------
	"wooden_shield": {"name": "Wooden Shield", "type": "shield", "value": 36, "block": 0.5, "desc": "Planks and an iron rim."},
	"kite_shield": {"name": "Kite Shield", "type": "shield", "value": 110, "block": 0.75, "desc": "A tall shield in the knightly style."},
	# --- clothing ----------------------------------------------------------------
	"wool_cloak": {"name": "Wool Cloak", "type": "cloak", "value": 30, "insulation": 18, "desc": "Keeps out the evening chill."},
	"fur_cloak": {"name": "Fur Cloak", "type": "cloak", "value": 90, "insulation": 40, "desc": "Northern furs. Essential in the Frostlands."},
	"desert_robes": {"name": "Desert Robes", "type": "cloak", "value": 55, "insulation": 6, "heat": 0.5, "desc": "Loose linen that halves the desert's thirst."},
	"silk_cloak": {"name": "Silk Cloak", "type": "cloak", "value": 220, "insulation": 22, "charm": 10, "rare": true, "desc": "Eastern silk. Nobles take notice."},
	"leather_armor": {"name": "Leather Armour", "type": "armor", "value": 80, "armor": 0.15, "desc": "Boiled leather."},
	"chainmail": {"name": "Chainmail Hauberk", "type": "armor", "value": 200, "armor": 0.3, "desc": "Riveted rings of steel."},
	"plate_armor": {"name": "Plate Armour", "type": "armor", "value": 480, "armor": 0.45, "desc": "A knight's full harness."},
	# --- tools -------------------------------------------------------------------
	"torch": {"name": "Torch", "type": "tool", "value": 3, "desc": "Lights the way. Press T to raise it."},
	"bedroll": {"name": "Bedroll", "type": "tool", "value": 25, "desc": "Sleep under the stars (use from the inventory)."},
	"campfire_kit": {"name": "Campfire Kit", "type": "tool", "value": 6, "desc": "Flint and kindling. Use it to build a campfire."},
	"bandage": {"name": "Linen Bandage", "type": "food", "value": 4, "health": 25, "desc": "Binds wounds."},
	"healing_draught": {"name": "Healing Draught", "type": "food", "value": 20, "health": 60, "desc": "A bitter herbal tonic."},
	# --- valuables -----------------------------------------------------------------
	"silver_ring": {"name": "Silver Ring", "type": "valuable", "value": 40, "desc": "Engraved with a forgotten crest."},
	"gold_necklace": {"name": "Gold Necklace", "type": "valuable", "value": 75, "desc": "Heavy and finely made."},
	"ruby": {"name": "Ruby", "type": "valuable", "value": 96, "desc": "Deep red, flawless."},
	"emerald": {"name": "Emerald", "type": "valuable", "value": 110, "desc": "Green as the Thornwood in spring."},
	"ancient_coin": {"name": "Ancient Coin", "type": "valuable", "value": 30, "desc": "Minted by a kingdom long fallen."},
	"falcon_charm": {"name": "Falconer's Charm", "type": "valuable", "value": 60, "rare": true, "desc": "A hooded-falcon token. Nobles respect its bearer (+reputation)."},
}

static func get_item(id: String) -> Dictionary:
	return DB.get(id, {"name": id, "type": "misc", "value": 1, "desc": ""})

static func display_name(id: String) -> String:
	return get_item(id).get("name", id)

static func price_text(silver: int) -> String:
	var g := silver / SILVER_PER_GOLD
	var s := silver % SILVER_PER_GOLD
	if g > 0 and s > 0:
		return "%d gold, %d silver" % [g, s]
	if g > 0:
		return "%d gold" % g
	return "%d silver" % s
