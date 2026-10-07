local Template = {}

Template.Id = "T19"
Template.Name = "Great Divide"
Template.Width = 27
Template.Height = 32

Template.Grid = {
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "NEU", "POI", "POI", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "HZD", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "NEU", "NEU", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "POI", "NEU", "NEU" },
	{ "NEU", "NEU", "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "ADV", "ADV", "NEU", "NEU", "ADV" },
	{ "SLW", "SLW", "NEU", "SLW", "SLW", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "NEU", "ADV", "ADV" },
	{ "SLW", "SLW", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "ADV" },
	{ "SLW", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "WAT", "WAT", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "ADV" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "WAT", "WAT", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "HZD", "HZD", "LAN", "LAN", "NEU", "ADV", "NEU", "ADV", "ADV", "ADV", "ADV", "ADV", "LAN", "NEU", "NEU", "NEU", "NEU", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "HZD", "HZD", "LAN", "LAN", "SLW", "SLW", "SLW", "ADV", "ADV", "ADV", "ADV", "LAN", "LAN", "WAT", "WAT", "NEU", "WAT", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "HZD", "HZD", "LAN", "LAN", "SLW", "SLW", "SLW", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "WAT", "WAT", "WAT", "WAT", "HZD", "HZD", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "OBS", "OBS", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "WAT", "WAT", "OBS", "OBS", "NEU", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "ED", "ED", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "ED", "ED" },
	{ "ED", "ED", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "ED", "ED" },
	{ "ED", "ED", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "PD", "PD", "PD", "PD", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "ED", "ED" },
	{ "NEU", "NEU", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "OBS", "OBS", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "OBS", "OBS", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "SLW", "SLW", "NEU", "OBS", "OBS", "WAT", "WAT", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "SLW", "SLW", "HZD", "OBS", "OBS", "WAT", "WAT", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "ADV", "NEU", "HZD", "HZD", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "SLW", "SLW", "HZD", "HZD", "HZD", "HZD", "WAT", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "ADV", "HZD", "HZD", "HZD", "LAN", "LAN", "LAN", "ADV", "ADV", "ADV", "SLW", "SLW", "NEU", "HZD", "HZD", "LAN", "LAN", "LAN", "NEU", "NEU" },
	{ "NEU", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "ADV", "HZD", "NEU", "HZD", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "SLW", "SLW", "NEU", "HZD", "HZD", "LAN", "LAN", "NEU", "NEU", "NEU" },
	{ "NEU", "NEU", "ADV", "NEU", "NEU", "LAN", "LAN", "LAN", "POI", "POI", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "NEU" },
	{ "NEU", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "LAN", "LAN", "POI", "POI", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "NEU", "NEU", "HZD", "HZD", "NEU" },
	{ "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "HZD", "HZD", "NEU" },
	{ "ADV", "ADV", "NEU", "WAT", "NEU", "HZD", "HZD", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "HZD", "HZD", "NEU" },
	{ "NEU", "WAT", "WAT", "WAT", "HZD", "HZD", "HZD", "ADV", "NEU", "NEU", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "LAN", "POI", "POI", "NEU", "NEU", "NEU", "WAT", "WAT", "NEU" },
	{ "OBS", "NEU", "NEU", "WAT", "ADV", "ADV", "ADV", "ADV", "POI", "POI", "NEU", "LAN", "LAN", "LAN", "LAN", "LAN", "NEU", "NEU", "NEU", "POI", "POI", "NEU", "NEU", "NEU", "WAT", "NEU", "NEU" },
	{ "OBS", "OBS", "NEU", "WAT", "POI", "POI", "ADV", "POI", "POI", "NEU", "NEU", "NEU", "ED", "ED", "ED", "NEU", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "WAT", "NEU", "NEU" },
	{ "OBS", "OBS", "NEU", "POI", "POI", "POI", "POI", "POI", "NEU", "NEU", "NEU", "NEU", "ED", "ED", "ED", "ADV", "ADV", "ADV", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU", "NEU" },
}

return Template
