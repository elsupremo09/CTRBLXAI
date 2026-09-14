local Template = {}

Template.Id = "T07"
Template.Name = "Wave Survival"
Template.Width = 30
Template.Height = 30

Template.Grid = {
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "LAN", "NEU", "NEU", "LAN", "LAN", "BLK", "BLK", "LAN", "LAN", "LAN", "NEU", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "HZD", "BLK", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "BLK", "BLK", "BLK", "HZD", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "ADV", "ADV", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "PD", "PD", "PD", "PD", "PD", "PD", "ADV", "HZD", "HZD", "LAN", "LAN", "LAN", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "BLK", "LAN", "LAN", "HZD", "BLK", "HZD", "PD", "PD", "PD", "PD", "PD", "PD", "ADV", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "BLK", "LAN", "LAN", "HZD", "BLK", "ADV", "PD", "PD", "PD", "PD", "PD", "PD", "ADV", "BLK", "HZD", "LAN", "LAN", "BLK", "LAN", "LAN", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "BLK", "ADV", "PD", "PD", "PD", "PD", "PD", "PD", "HZD", "BLK", "HZD", "LAN", "LAN", "BLK", "LAN", "LAN", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "ADV", "PD", "PD", "PD", "PD", "PD", "PD", "HZD", "BLK", "HZD", "LAN", "LAN", "LAN", "LAN", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "PD", "PD", "PD", "PD", "PD", "PD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "ADV", "ADV", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "HZD", "BLK", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "BLK", "BLK", "BLK", "HZD", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "LAN", "LAN", "LAN", "BLK", "BLK", "LAN", "LAN", "LAN", "NEU", "LAN", "LAN", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "LAN", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
}

return Template
