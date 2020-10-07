"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AthleticChecker = void 0;
const axios_1 = __importDefault(require("axios"));
const querystring_1 = __importDefault(require("querystring"));
const moment_1 = __importDefault(require("moment"));
class AthleticChecker {
    constructor(config) {
        this.config = config;
    }
    deckToString(deck) {
        const deckText = '#ygopro-server deck log\n#main\n' + deck.main.join('\n') + '\n!side\n' + deck.side.join('\n') + '\n';
        return deckText;
    }
    async getAthleticDecks() {
        if (this.athleticDeckCache && moment_1.default().diff(this.lastAthleticDeckFetchTime, "seconds") < this.config.ttl) {
            return this.athleticDeckCache;
        }
        const { data } = await axios_1.default.get(this.config.rankURL, {
            timeout: 10000,
            responseType: "json",
            paramsSerializer: querystring_1.default.stringify,
            params: this.config.athleticFetchParams
        });
        const athleticDecks = data.slice(0, this.config.rankCount).map(m => m.name);
        this.athleticDeckCache = athleticDecks;
        this.lastAthleticDeckFetchTime = moment_1.default();
        return athleticDecks;
    }
    async getDeckType(deck) {
        const deckString = this.deckToString(deck);
        const { data } = await axios_1.default.post(this.config.identifierURL, querystring_1.default.stringify({ deck: deckString }), {
            timeout: 10000,
            responseType: "json"
        });
        return data.deck;
    }
    async checkAthletic(deck) {
        try {
            const athleticDecks = await this.getAthleticDecks();
            const deckType = await this.getDeckType(deck);
            const athletic = athleticDecks.includes(deckType);
            return { success: true, athletic, message: null };
        }
        catch (e) {
            return { success: false, message: e.toString() };
        }
    }
}
exports.AthleticChecker = AthleticChecker;
//# sourceMappingURL=athletic-check.js.map