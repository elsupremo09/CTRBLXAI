local Template = {}

Template.Id = "T02"
Template.Name = "Split Pressure"
Template.Width = 30
Template.Height = 19

Template.Grid = {
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "POI", "POI", "POI", "POI", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "POI", "POI", "POI", "POI", "POI", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "POI", "POI" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "POI", "POI" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "POI", "POI" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "POI", "POI" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "POI", "POI" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "POI", "POI" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "POI", "POI", "POI", "POI", "POI", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "POI", "POI", "POI", "POI", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
}

return Template
