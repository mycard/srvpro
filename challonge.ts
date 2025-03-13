import axios from 'axios';
import { createLogger } from 'bunyan';
import moment, { Moment } from 'moment';
import PQueue from 'p-queue';
import _ from 'underscore';

export interface Match {
  id: number;
  state: 'pending' | 'open' | 'complete'; // pending: 还未开始，open: 进行中，complete: 已结束
  player1_id: number;
  player2_id: number;
  winner_id?: number | 'tie'; // 如果存在，则代表该比赛已经结束
  scores_csv: string; // 2-1
}

export interface MatchWrapper {
  match: Match;
}

export interface Participant {
  id: number;
  name: string;
}

export interface ParticipantWrapper {
  participant: Participant;
}

export interface Tournament {
  id: number;
  participants: ParticipantWrapper[];
  matches: MatchWrapper[];
}

export interface TournamentWrapper {
  tournament: Tournament;
}

export interface MatchPost {
  scores_csv: string;
  winner_id?: number | 'tie';
}

export interface ChallongeConfig {
  api_key: string;
  tournament_id: string;
  cache_ttl: number;
  challonge_url: string;
}

export class Challonge {
  constructor(private config: ChallongeConfig) { }

  private queue = new PQueue({ concurrency: 1 })
  private log = createLogger({ name: 'challonge' });
  
  private previous: Tournament;
  private previousTime: Moment;

  private async getTournamentProcess(noCache = false) {
    if(!noCache && this.previous && this.previousTime.isAfter(moment().subtract(this.config.cache_ttl, 'ms'))) {
      return this.previous;
    }
    try {
      const { data: { tournament } } = await axios.get<TournamentWrapper>(
        `${this.config.challonge_url}/v1/tournaments/${this.config.tournament_id}.json`,
        {
          params: {
            api_key: this.config.api_key,
            include_participants: 1,
            include_matches: 1,
          },
          timeout: 5000,
        },
      );
      this.previous = tournament;
      this.previousTime = moment();
      return tournament;
    } catch (e) {
      this.log.error(`Failed to get tournament ${this.config.tournament_id}: ${e}`);
      return;
    }
  }

  async getTournament(noCache = false) {
    if (noCache) {
      return this.getTournamentProcess(noCache);
    }
    return this.queue.add(() => this.getTournamentProcess())
  }

  async putScore(matchId: number, match: MatchPost, retried = 0) { 
    try {
      await axios.put(
        `${this.config.challonge_url}/v1/tournaments/${this.config.tournament_id}/matches/${matchId}.json`,
        {
          api_key: this.config.api_key,
          match: match,
        },
      );
      this.previous = undefined;
      this.previousTime = undefined;
      return true;
    } catch (e) {
      this.log.error(`Failed to put score for match ${matchId}: ${e}`);
      if (retried < 5) { 
        this.log.info(`Retrying match ${matchId}`);
        return this.putScore(matchId, match, retried + 1);
      } else {
        this.log.error(`Failed to put score for match ${matchId} after 5 retries`);
        return false;
      }
    }
  }

  async clearParticipants() { 
    try {
      await axios.delete(`${this.config.challonge_url}/v1/tournaments/${this.config.tournament_id}/participants/clear.json`, {
        params: {
            api_key: this.config.api_key
        },
        validateStatus: () => true,
      })
      return true;
    } catch (e) {
      this.log.error(`Failed to clear participants for tournament ${this.config.tournament_id}: ${e}`);
      return false;
    }
  }

  async uploadParticipants(participantNames: string[]) { 
    try {
      await axios.post(`${this.config.challonge_url}/v1/tournaments/${this.config.tournament_id}/participants/bulk_add.json`, {
        api_key: this.config.api_key,
        participants: participantNames.map(name => ({ name })),
      });
      return true;
    } catch (e) {
      this.log.error(`Failed to upload participants for tournament ${this.config.tournament_id}: ${e}`);
      return false;
    }
  }
}
