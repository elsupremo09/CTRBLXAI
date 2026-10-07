local Template = {}

Template.Id = "T20"
Template.Name = "River Vale"
Template.Width = 21
Template.Height = 28

Template.Grid = {
	{ "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "PD", "PD" },
	{ "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "PD", "PD" },
	{ "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU" },
	{ "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "LAN", "HZD", "OBS", "OBS", "LAN", "LAN", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "HZD", "OBS", "OBS", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "LAN", "HZD", "OBS", "OBS", "NEU", "POI", "POI" },
	{ "NEU", "NEU", "NEU", "HZD", "HZD", "OBS", "OBS", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "HZD", "HZD", "POI", "POI" },
	{ "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "HZD", "NEU", "POI", "POI" },
	{ "NEU", "ADV", "ADV", "NEU", "HZD", "HZD", "HZD", "LAN", "LAN", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "POI", "POI" },
	{ "ADV", "ADV", "ADV", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "SLW", "NEU", "NEU" },
	{ "ADV", "NEU", "NEU", "SLW", "SLW", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "SLW", "SLW", "SLW", "ADV" },
	{ "ADV", "NEU", "NEU", "NEU", "SLW", "LAN", "LAN", "SLW", "SLW", "SLW", "LAN", "SLW", "SLW", "SLW", "LAN", "LAN", "NEU", "NEU", "SLW", "SLW", "ADV" },
	{ "NEU", "NEU", "NEU", "SLW", "SLW", "LAN", "LAN", "SLW", "SLW", "SLW", "LAN", "SLW", "SLW", "SLW", "LAN", "LAN", "NEU", "HZD", "HZD", "ADV", "ADV" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "SLW", "ED", "ED", "ED", "ED", "ED", "SLW", "LAN", "LAN", "NEU", "HZD", "HZD", "ADV", "ADV" },
	{ "NEU", "POI", "NEU", "WAT", "WAT", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "ADV" },
	{ "NEU", "POI", "WAT", "WAT", "NEU", "LAN", "LAN", "LAN", "ED", "ED", "ED", "ED", "ED", "LAN", "LAN", "LAN", "NEU", "POI", "POI", "POI", "NEU" },
	{ "NEU", "POI", "NEU", "WAT", "NEU", "LAN", "LAN", "SLW", "ED", "ED", "ED", "ED", "ED", "SLW", "LAN", "LAN", "NEU", "NEU", "NEU", "POI", "NEU" },
	{ "NEU", "POI", "SLW", "SLW", "NEU", "LAN", "LAN", "SLW", "SLW", "SLW", "LAN", "SLW", "SLW", "SLW", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "POI", "SLW", "SLW", "SLW", "LAN", "LAN", "SLW", "SLW", "SLW", "LAN", "SLW", "SLW", "SLW", "LAN", "LAN", "HZD", "OBS", "OBS", "OBS", "NEU" },
	{ "NEU", "NEU", "NEU", "SLW", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "HZD", "WAT", "OBS", "OBS", "NEU" },
	{ "NEU", "NEU", "HZD", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "LAN", "SLW", "SLW", "SLW", "HZD", "WAT", "WAT", "WAT", "NEU" },
	{ "NEU", "NEU", "HZD", "HZD", "NEU", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "LAN", "SLW", "SLW", "SLW", "HZD", "WAT", "WAT", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "OBS", "OBS", "ADV", "ADV", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "OBS", "OBS", "ADV", "ADV", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "OBS", "OBS", "HZD", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "NEU", "NEU", "NEU" },
	{ "NEU", "LAN", "LAN", "LAN", "OBS", "OBS", "HZD", "LAN", "LAN", "LAN", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU" },
	{ "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU" },
	{ "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "PD", "PD" },
	{ "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "PD", "PD" },
}

return Template
