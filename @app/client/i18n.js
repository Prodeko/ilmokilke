module.exports = {
  locales: ["fi", "en"],
  defaultLocale: "fi",
  pages: {
    "*": ["common", "error"],
    "/404": ["error"],
    "/": ["home", "events"],
    "/create-event-category": ["events"],
    "/update-registration/[updateToken]": ["register"],
    "rgx:^/admin": ["admin", "events"],
    "rgx:^/event": ["events", "register"],
  },
  loadLocaleFrom: (lang, ns) =>
    import(`./src/translations/${lang}/${ns}.json`).then((m) => m.default),
};
