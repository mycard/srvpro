import axios from 'axios';
import { createLogger } from 'bunyan';
import moment, { Moment } from 'moment';
import PQueue from 'p-queue';

export interface Match {
  attachment_count?: any;
  created_at: string;
  group_id?: any;
  has_attachment: boolean;
  id: number;
  identifier: string;
  location?: any;
  loser_id?: any;
  player1_id: number;
  player1_is_prereq_match_loser: boolean;
  player1_prereq_match_id?: any;
  player1_votes?: any;
  player2_id: number;
  player2_is_prereq_match_loser: boolean;
  player2_prereq_match_id?: any;
  player2_votes?: any;
  round: number;
  scheduled_time?: any;
  started_at: string;
  state: string;
  tournament_id: number;
  underway_at?: any;
  updated_at: string;
  winner_id?: any;
  prerequisite_match_ids_csv: string;
  scores_csv: string;
}

export interface MatchWrapper {
  match: Match;
}

export interface Participant {
  active: boolean;
  checked_in_at?: any;
  created_at: string;
  final_rank?: any;
  group_id?: any;
  icon?: any;
  id: number;
  invitation_id?: any;
  invite_email?: any;
  misc?: any;
  name: string;
  on_waiting_list: boolean;
  seed: number;
  tournament_id: number;
  updated_at: string;
  challonge_username?: any;
  challonge_email_address_verified?: any;
  removable: boolean;
  participatable_or_invitation_attached: boolean;
  confirm_remove: boolean;
  invitation_pending: boolean;
  display_name_with_invitation_email_address: string;
  email_hash?: any;
  username?: any;
  attached_participatable_portrait_url?: any;
  can_check_in: boolean;
  checked_in: boolean;
  reactivatable: boolean;
}

export interface ParticipantWrapper {
  participant: Participant;
}

export interface Tournament {
  accept_attachments: boolean;
  allow_participant_match_reporting: boolean;
  anonymous_voting: boolean;
  category?: any;
  check_in_duration?: any;
  completed_at?: any;
  created_at: string;
  created_by_api: boolean;
  credit_capped: boolean;
  description: string;
  game_id: number;
  group_stages_enabled: boolean;
  hide_forum: boolean;
  hide_seeds: boolean;
  hold_third_place_match: boolean;
  id: number;
  max_predictions_per_user: number;
  name: string;
  notify_users_when_matches_open: boolean;
  notify_users_when_the_tournament_ends: boolean;
  open_signup: boolean;
  participants_count: number;
  prediction_method: number;
  predictions_opened_at?: any;
  private: boolean;
  progress_meter: number;
  pts_for_bye: string;
  pts_for_game_tie: string;
  pts_for_game_win: string;
  pts_for_match_tie: string;
  pts_for_match_win: string;
  quick_advance: boolean;
  ranked_by: string;
  require_score_agreement: boolean;
  rr_pts_for_game_tie: string;
  rr_pts_for_game_win: string;
  rr_pts_for_match_tie: string;
  rr_pts_for_match_win: string;
  sequential_pairings: boolean;
  show_rounds: boolean;
  signup_cap?: any;
  start_at?: any;
  started_at: string;
  started_checking_in_at?: any;
  state: string;
  swiss_rounds: number;
  teams: boolean;
  tie_breaks: string[];
  tournament_type: string;
  updated_at: string;
  url: string;
  description_source: string;
  subdomain?: any;
  full_challonge_url: string;
  live_image_url: string;
  sign_up_url?: any;
  review_before_finalizing: boolean;
  accepting_predictions: boolean;
  participants_locked: boolean;
  game_name: string;
  participants_swappable: boolean;
  team_convertable: boolean;
  group_stages_were_started: boolean;
  participants: ParticipantWrapper[];
  matches: MatchWrapper[];
}

export interface TournamentWrapper {
  tournament: Tournament;
}

export interface MatchPost {
  scores_csv: string;
  winner_id: number;
}

export interface ChallongeConfig {
  api_key: string;
  tournament_id: string;
  cache_ttl: number;
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
        `https://api.challonge.com/v1/tournaments/${this.config.tournament_id}.json`,
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
      this.log.error(`Failed to get tournament ${this.config.tournament_id}`, e);
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
        `https://api.challonge.com/v1/tournaments/${this.config.tournament_id}/matches/${matchId}.json`,
        {
          api_key: this.config.api_key,
          match: match,
        },
      );
      this.previous = undefined;
      this.previousTime = undefined;
      return true;
    } catch (e) {
      this.log.error(`Failed to put score for match ${matchId}`, e);
      if (retried < 5) { 
        this.log.info(`Retrying match ${matchId}`);
        return this.putScore(matchId, match, retried + 1);
      } else {
        this.log.error(`Failed to put score for match ${matchId} after 5 retries`);
        return false;
      }
    }
  }
}
