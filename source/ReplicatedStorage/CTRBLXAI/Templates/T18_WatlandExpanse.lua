local Template = {}

Template.Id = "T18"
Template.Name = "Watland Expanse"
Template.Width = 27
Template.Height = 24

Template.Grid = {
	{ "POI", "POI", "NEU", "NEU", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "ADV", "NEU", "ADV" },
	{ "POI", "POI", "POI", "POI", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "HZD", "NEU", "ADV", "ADV", "ADV" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "HZD", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "ADV", "OBS", "OBS", "NEU", "NEU", "HZD", "NEU", "POI", "NEU", "ADV" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "OBS", "OBS", "NEU", "NEU", "HZD", "POI", "POI", "POI", "NEU" },
	{ "PD", "PD", "PD", "PD", "PD", "PD", "LAN", "LAN", "HZD", "HZD", "ADV", "ADV", "SLW", "SLW", "LAN", "LAN", "NEU", "NEU", "OBS", "OBS", "NEU", "NEU", "HZD", "POI", "POI", "NEU", "NEU" },
	{ "NEU", "NEU", "SLW", "SLW", "SLW", "NEU", "LAN", "LAN", "HZD", "HZD", "ADV", "ADV", "SLW", "SLW", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "SLW", "SLW", "NEU", "NEU", "LAN", "LAN", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "HZD", "NEU", "WAT", "WAT", "NEU", "ADV", "ADV", "ADV", "NEU", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "HZD", "HZD", "WAT", "WAT", "NEU", "ADV", "ADV", "ADV", "NEU", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "NEU", "ADV", "ADV", "NEU", "NEU", "OBS", "OBS", "NEU", "NEU", "NEU", "NEU" },
	{ "HZD", "NEU", "NEU", "WAT", "NEU", "NEU", "NEU", "ADV", "ADV", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "NEU", "ADV", "NEU", "NEU", "NEU", "OBS", "OBS", "POI", "POI", "NEU", "NEU" },
	{ "SLW", "SLW", "NEU", "WAT", "NEU", "NEU", "NEU", "ADV", "ADV", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "NEU", "OBS", "OBS", "POI", "POI", "NEU", "NEU" },
	{ "SLW", "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "NEU", "OBS", "OBS", "NEU", "NEU", "NEU", "NEU" },
	{ "SLW", "NEU", "NEU", "NEU", "NEU", "OBS", "OBS", "OBS", "OBS", "LAN", "LAN", "OBS", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "HZD", "NEU", "NEU", "NEU", "NEU", "OBS", "OBS", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "HZD", "HZD", "NEU", "NEU", "NEU", "OBS", "OBS", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "WAT", "WAT", "WAT", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "WAT", "WAT", "WAT", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "HZD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "WAT", "WAT", "WAT", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "ED", "ED", "ED" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "HZD", "NEU", "NEU", "NEU", "NEU", "HZD" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "NEU", "NEU", "SLW", "SLW", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "NEU", "NEU", "WAT", "HZD", "HZD" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "SLW", "NEU", "NEU", "NEU", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "NEU", "NEU", "WAT", "WAT", "HZD" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "NEU", "NEU", "NEU", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "POI", "ADV", "WAT", "WAT" },
	{ "NEU", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "HZD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "POI", "ADV", "ADV", "WAT", "WAT" },
	{ "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "NEU", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "SLW", "ADV", "ADV", "ADV", "WAT", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "SLW", "SLW", "NEU", "NEU", "ADV", "NEU", "NEU" },
}

return Template
