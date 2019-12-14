class ReviewBiddingController < ApplicationController

  require 'rgl/adjacency'
  require 'rgl/dot'
  require 'rgl/topsort'

  def action_allowed?
    case params[:action]
    when 'review_bid', 'set_priority'
      ['Instructor',
       'Teaching Assistant',
       'Administrator',
       'Super-Administrator',
       'Student'].include? current_role_name and
      ((%w[list].include? action_name) ? are_needed_authorizations_present?(params[:id], "reader", "submitter", "reviewer") : true)
    else
      ['Instructor',
       'Teaching Assistant',
       'Administrator',
       'Super-Administrator'].include? current_role_name
    end
  end


  def review_bid
    @participant = AssignmentParticipant.find(params[:id].to_i)
    @assignment = @participant.assignment
    # @slots_filled = SignUpTopic.find_slots_filled(@assignment.id)
    # @slots_waitlisted = SignUpTopic.find_slots_waitlisted(@assignment.id)
    # @show_actions = true
    # @priority = 0
    #@sign_up_topics = SignUpTopic.where(assignment_id: @assignment.id, private_to: nil)
    team_id = @participant.team.try(:id)
    my_topic = SignedUpTeam.where(team_id: team_id).select(:topic_id)
    @sign_up_topics = SignUpTopic.where(["assignment_id = ? and id != ?", @assignment.id.to_s, my_topic.to_s])
    @max_team_size = @assignment.max_team_size

    @selected_topics =nil
    # if @assignment.is_intelligent
      @bids = team_id.nil? ? [] : ReviewBid.where(participant_id: team_id).order(:priority)
      # signed_up_topics = []
      # @bids.each do |bid|
      #   sign_up_topic = SignUpTopic.find_by(id: bid.topic_id)
      #   signed_up_topics << sign_up_topic if sign_up_topic
      # end
      # signed_up_topics &= @sign_up_topics
      # @sign_up_topics -= signed_up_topics
      # @bids = signed_up_topics
    # end
    #
    @num_of_topics = @sign_up_topics.size
    # @signup_topic_deadline = @assignment.due_dates.find_by(deadline_type_id: 7)
    # @drop_topic_deadline = @assignment.due_dates.find_by(deadline_type_id: 6)
    # @student_bids = team_id.nil? ? [] : Bid.where(team_id: team_id)
    #
    # unless @assignment.due_dates.find_by(deadline_type_id: 1).nil?
    #   @show_actions = false if !@assignment.staggered_deadline? and @assignment.due_dates.find_by(deadline_type_id: 1).due_at < Time.now
    #
    #   # Find whether the user has signed up for any topics; if so the user won't be able to
    #   # sign up again unless the former was a waitlisted topic
    #   # if team assignment, then team id needs to be passed as parameter else the user's id
    #   users_team = SignedUpTeam.find_team_users(@assignment.id, session[:user].id)
    #   @selected_topics = if users_team.empty?
    #                        nil
    #                      else
    #                        # TODO: fix this; cant use 0
    #                        SignedUpTeam.find_user_signup_topics(@assignment.id, users_team[0].t_id)
    #                      end
    # end
    render 'sign_up_sheet/review_bid' #and return if @assignment.is_intelligent
    
  end

  def run_intelligent_assignment
    priority_info = []
    assignment = Assignment.find_by(id: params[:id])
    topics = assignment.sign_up_topics
    teams = assignment.teams
    teams.each do |team|
      # Exclude any teams already signed up
      next if SignedUpTeam.where(team_id: team.id, is_waitlisted: 0).any?
      # Grab student id and list of bids
      bids = []
      topics.each do |topic|
        bid_record = Bid.find_by(team_id: team.id, topic_id: topic.id)
        bids << (bid_record.nil? ? 0 : bid_record.priority ||= 0)
      end
      team.users.each {|user| priority_info << {pid: user.id, ranks: bids} if bids.uniq != [0] }
    end
    bidding_data = {users: priority_info, max_team_size: assignment.max_team_size}
    ExpertizaLogger.info LoggerMessage.new(controller_name, session[:user].name, "Bidding data for assignment #{assignment.name}: #{bidding_data}", request)
    url = WEBSERVICE_CONFIG["topic_bidding_webservice_url"]
    begin
      response = RestClient.post url, bidding_data.to_json, content_type: :json, accept: :json
      teams = JSON.parse(response)["teams"]
      ExpertizaLogger.info LoggerMessage.new(controller_name, session[:user].name, "Team formation info for assignment #{assignment.name}: #{teams}", request)
      create_new_teams_for_bidding_response(teams, assignment, priority_info)
      match_new_teams_to_topics(assignment)
    rescue StandardError => e
      flash[:error] = e.message
    end
    redirect_to controller: 'tree_display', action: 'list'
  end

  def set_priority
    participant = AssignmentParticipant.find_by(id: params[:participant_id])
    # assignment_id = SignUpTopic.find(params[:topic].first).assignment.id
    # team_id = participant.team.try(:id)
    # if params[:topic].nil?
    #   # All topics are deselected by current team
    #   ReviewBid.where(participant_id: params[:participant_id]).destroy_all
    # else
    #   @bids = ReviewBid.where(participant_id: params[:participant_id])
    #   signed_up_topics = ReviewBid.where(participant_id: params[:participant_id]).map(&:topic_id)
    #   # Remove topics from bids table if the student moves data from Selection table to Topics table
    #   # This step is necessary to avoid duplicate priorities in Bids table
    #   signed_up_topics -= params[:topic].map(&:to_i)
    #   signed_up_topics.each do |topic|
    #     ReviewBid.where(topic_id: topic, team_id: team_id).destroy_all
    #   end
    #   params[:topic].each_with_index do |topic_id, index|
    #     bid_existence = Bid.where(sign_up_topic_id: topic_id, participant_id: params[:participant_id])
    #     if bid_existence.empty?
    #       ReviewBid.create(priority: index + 1,sign_up_topic_id: topic_id, participant_id: params[:participant_id],assignment_id: assignment_id)
    #     else
    #       ReviewBid.where(sign_up_topic_id: topic_id, participant_id: params[:participant_id]).update_all(priority: index + 1)
    #     end
    #   end
    # end
    redirect_to action: 'sign_up_sheet/list', assignment_id: params[:assignment_id]
  end

end
