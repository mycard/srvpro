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
  scores_csv?: string; // 比分，2-1 这样的格式，请保证和上传的情况相同
}

export interface MatchWrapper {
  match: Match;
}

export interface Participant {
  id: number;
  name: string; // 玩家的名称，影响玩家的进服匹配
  deckbuf?: string; // 玩家的卡组。如果存在，那么卡组由比赛系统管理。base64
  // 构造方法: [uint32 maincount+extracount][uint32 sideccount][uint32 card1][uint32 card2]...
  // 示例: NwAAAA8AAAC8beUDdgljAnYJYwJ2CWMCEUKKAxFCigOzoLECB1ekBQdXpAUHV6QFPO4FAzzuBQOSZMQEziwNBM4sDQTOLA0EryPeAK8j3gCvI94AKpVlASqVZQEqlWUBTkEDAE5BAwBOQQMAUI+IAFCPiABQj4gA+twUAaab9AGEoUIBwsdyAcLHcgHCx3IBPRWmBSJImQAiSJkAIkiZADdj4QF8oe8FpFt8A5chZAW1XJ8APXyNAMYzYwOIEXYDtfABBavrrQBq4agDn5BqANCkFwEJWmMAWfK5A3OVmwF8e+QD1xqfAdcanwF99r8Affa/AB43ggEeN4IBhCV+AIQlfgCEJX4APqRxAT6kcQE/OuoDb3bvAG927wC0/F4B
}

export interface ParticipantWrapper {
  participant: Participant;
}

export interface Tournament {
  id: number;
  participants: ParticipantWrapper[];
  matches: MatchWrapper[];
}

// GET /v1/tournaments/${tournament_id}.json?api_key=xxx&include_participants=1&include_matches=1 returns { tournament: Tournament }
export interface TournamentWrapper {
  tournament: Tournament;
}

// PUT /v1/tournaments/${tournament_id}/matches/${match_id}.json { api_key: string, match: MatchPost } returns ANY
export interface MatchPost {
  scores_csv: string; // 比分。2-1 这样的格式。可能有特殊情况，比如 -9-1 或者 1--9，代表有一方掉线，或是加时赛胜利。也就是允许负数（从第一串数字的最后一个 - 区分）
  winner_id?: number | 'tie'; // 上传比分的时候这个字段不一定存在。如果不存在的话代表比赛没打完（比如 1-0 就会上传，这时候换 side）
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

  // DELETE /v1/tournaments/${tournament_id}/participants/clear.json?api_key=xxx returns ANY
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

  // POST /v1/tournaments/${tournament_id}/participants/bulk_add.json { api_key: string, participants: { name: string }[] } returns ANY
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
