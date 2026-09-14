local Template = {}

Template.Id = "T05"
Template.Name = "Defense Center"
Template.Width = 30
Template.Height = 20

Template.Grid = {
	{ "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "PD", "PD" },
	{ "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "PD", "PD" },
	{ "ED", "ED", "ED", "ED", "ED", "ED", "ED", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "PD", "PD", "PD", "PD", "PD", "PD", "PD" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "ED", "ED", "ED", "ED", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "NEU", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "POI", "POI", "POI", "POI", "POI", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "NEU", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "POI", "POI", "POI", "POI", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "NEU", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "POI", "BLK", "BLK", "BLK", "BLK", "BLK", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "POI", "POI", "POI", "POI", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "POI", "POI", "POI", "POI", "POI", "POI", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "LAN", "LAN", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
}

return Template
