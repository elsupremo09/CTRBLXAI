local Template = {}

Template.Id = "T03"
Template.Name = "Broken Crossing"
Template.Width = 30
Template.Height = 20

Template.Grid = {
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "BLK", "WAT", "WAT", "WAT", "WAT", "WAT", "WAT", "WAT", "WAT", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "BLK", "WAT", "POI", "POI", "POI", "POI", "POI", "POI", "WAT", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "BLK", "WAT", "POI", "POI", "POI", "POI", "POI", "POI", "WAT", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "BLK", "BLK", "POI", "POI", "POI", "POI", "POI", "POI", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "POI", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "POI", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED" },
	{ "PD", "PD", "PD", "PD", "PD", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "BLK", "BLK", "BLK", "BLK", "BLK", "BLK", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "BLK", "BLK", "POI", "POI", "POI", "POI", "POI", "POI", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "BLK", "WAT", "POI", "POI", "POI", "POI", "POI", "POI", "WAT", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "BLK", "WAT", "POI", "POI", "POI", "POI", "POI", "POI", "WAT", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "BLK", "WAT", "WAT", "WAT", "WAT", "WAT", "WAT", "WAT", "WAT", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
}

return Template
