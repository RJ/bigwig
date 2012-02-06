%%
%% Gets added as a handler to SASL's error_logger
%% Broadcasts SASL reports to all registered client pids
%%
%% Used to stream new reports down a websocket.
%%
-module(bigwig_error_handler).
-behaviour(gen_event).

-export([add_sup_handler/0]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
        cdb       %% couchbeam handle, where we write sasl reports
    }).

%%%----------------------------------------------------------------------------

add_sup_handler() -> 
    gen_event:add_sup_handler(error_logger, ?MODULE, []).

%%%----------------------------------------------------------------------------

init([]) -> 
    Host = "localhost",
    Port = 5984,
    Prefix = "",
    Options = [],
    S = couchbeam:server_connection(Host, Port, Prefix, Options),
    {ok, Db} = couchbeam:open_or_create_db(S, "bigwig-sasl", []),
    {ok, #state{cdb=Db}}.

handle_event(Event, State) ->
    %%io:format("EVENT(to ~p) ~p\n", [length(State#state.listeners), Event]),
    Json = jsx:term_to_json(Event),
    DocId = make_id(),
    Doc = {[
            {<<"_id">>, DocId},
            {<<"report">>, Json}
        ]},
    {ok, Doc1} = couchbeam:save_doc(State#state.cdb, Doc),
    {Id,Rev} = couchbeam_doc:get_idrev(Doc1),
    {ok, _} = couchbeam:put_attachment( State#state.cdb, 
                                        Id, 
                                        "report.erlang", 
                                        term_to_binary(Event),
                                        [{rev,Rev},
                                         {content_type,<<"application/x-erlang-binary">>}] ),
    Msg = {?MODULE, Event},
    bigwig_pubsubhub:notify(Msg),
    {ok, State}.

handle_call(_Msg, State)   -> {ok, not_implemented, State}.

handle_info(_Info, State)  -> {ok, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%

make_id() -> iolist_to_binary(io_lib:format("~B", [unixtimehp()])).

unixtimehp() ->
    {Meg,S,Mic} = erlang:now(), 
    (Meg*1000000 + S)*1000000 + Mic.

