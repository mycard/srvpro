"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.Challonge = void 0;
const axios_1 = __importDefault(require("axios"));
const bunyan_1 = require("bunyan");
const moment_1 = __importDefault(require("moment"));
const p_queue_1 = __importDefault(require("p-queue"));
class Challonge {
    config;
    constructor(config) {
        this.config = config;
    }
    queue = new p_queue_1.default({ concurrency: 1 });
    log = (0, bunyan_1.createLogger)({ name: 'challonge' });
    previous;
    previousTime;
    async getTournamentProcess(noCache = false) {
        if (!noCache && this.previous && this.previousTime.isAfter((0, moment_1.default)().subtract(this.config.cache_ttl, 'ms'))) {
            return this.previous;
        }
        try {
            const { data: { tournament } } = await axios_1.default.get(`https://api.challonge.com/v1/tournaments/${this.config.tournament_id}.json`, {
                params: {
                    api_key: this.config.api_key,
                    include_participants: 1,
                    include_matches: 1,
                },
                timeout: 5000,
            });
            this.previous = tournament;
            this.previousTime = (0, moment_1.default)();
            return tournament;
        }
        catch (e) {
            this.log.error(`Failed to get tournament ${this.config.tournament_id}`, e);
            return;
        }
    }
    async getTournament(noCache = false) {
        if (noCache) {
            return this.getTournamentProcess(noCache);
        }
        return this.queue.add(() => this.getTournamentProcess());
    }
    async putScore(matchId, match, retried = 0) {
        try {
            await axios_1.default.put(`https://api.challonge.com/v1/tournaments/${this.config.tournament_id}/matches/${matchId}.json`, {
                api_key: this.config.api_key,
                match: match,
            });
            this.previous = undefined;
            this.previousTime = undefined;
            return true;
        }
        catch (e) {
            this.log.error(`Failed to put score for match ${matchId}`, e);
            if (retried < 5) {
                this.log.info(`Retrying match ${matchId}`);
                return this.putScore(matchId, match, retried + 1);
            }
            else {
                this.log.error(`Failed to put score for match ${matchId} after 5 retries`);
                return false;
            }
        }
    }
}
exports.Challonge = Challonge;
//# sourceMappingURL=challonge.js.map