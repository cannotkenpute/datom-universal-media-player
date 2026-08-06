(ns datomworld.media.controller
  "Pure media-player policy plus a Yang/Yin execution boundary."
  (:require
    [clojure.string :as str]
    [yang.clojure :as yang]
    [yin.vm :as vm]
    [yin.vm.ast-walker :as ast-walker]
    [yin.vm.register :as register]
    [yin.vm.stack :as stack]))


(def initial-state
  {:app/active-tab :player
   :converter/status :empty
   :converter/source nil
   :converter/output-name nil
   :converter/error nil
   :converter/error-detail nil
   :player/status :empty
   :player/source nil
   :player/media-kind nil
   :player/duration-seconds 0.0
   :player/position-seconds 0.0
   :player/buffered []
   :player/volume 1.0
   :player/muted? false
   :player/rate 1.0
   :player/fullscreen? false
   :player/seeking? false
   :player/error nil
   :player/next-command-id 0})


(defn event-kind
  [event]
  (or (:player.event/kind event) (:media.event/kind event)))


(defn- media-kind
  [mime-type]
  (cond
    (str/starts-with? (or mime-type "") "audio/") :audio
    (str/starts-with? (or mime-type "") "video/") :video
    :else :unknown))


(defn- finite-number?
  [x]
  (and (number? x)
       #?(:clj (Double/isFinite (double x))
          :cljs (js/Number.isFinite x)
          :cljd true)))


(defn- clamp
  [x low high]
  (max low (min high x)))


(defn- source-id
  [state]
  (get-in state [:player/source :media/source-id]))


(defn- source-generation
  [state]
  (get-in state [:player/source :media/source-generation]))


(defn- converter-source-id
  [state]
  (get-in state [:converter/source :media/source-id]))


(defn- converter-source-generation
  [state]
  (get-in state [:converter/source :media/source-generation]))


(defn- stale-source-event?
  [state event]
  (when-let [event-source (:media/source-id event)]
    (or (not= event-source (source-id state))
        (not= (:media/source-generation event)
              (source-generation state)))))


(defn- stale-converter-event?
  [state event]
  (or (not= (:media/source-id event)
            (converter-source-id state))
      (not= (:media/source-generation event)
            (converter-source-generation state))))


(defn- stale-source-selection?
  [state event]
  (let [current (source-generation state)
        incoming (:media/source-generation event)]
    (and (number? current)
         (number? incoming)
         (<= incoming current))))


(defn- command-for-source
  [state source kind values]
  (let [id (:player/next-command-id state 0)]
    [(update state :player/next-command-id inc)
     (merge {:media.command/id id
             :media.command/kind kind}
            (select-keys source
                         [:media/source-id :media/source-generation])
            values)]))


(defn- command
  [state kind values]
  (command-for-source state (:player/source state) kind values))


(defn- media-result
  ([state] (media-result state [] []))
  ([state media-commands settings-commands]
   {:state state
    :media-commands (vec media-commands)
    :settings-commands (vec settings-commands)
    :view-model state}))


(defn- settings-command
  [state]
  {:settings.command/kind :save
   :settings/value
   {:player/volume (:player/volume state)
    :player/muted? (:player/muted? state)
    :player/rate (:player/rate state)}})


(defn transition
  "Apply one normalized event. Media commands express intent; only observed
   media events update actual playback state."
  [state event]
  (let [state (or state initial-state)
        kind (event-kind event)]
    (if (and (not (contains? #{:source-selected
                               :converter/source-selected
                               :converter/selection-failed
                               :converter/file-converted
                               :converter/failed}
                             kind))
             (stale-source-event? state event))
      (media-result state)
      (case kind
        :ui/select-tab
        (if (contains? #{:player :converter} (:app/tab event))
          (media-result (assoc state :app/active-tab (:app/tab event)))
          (media-result state))

        :converter/source-selected
        (let [source (select-keys event
                                  [:media/source-id
                                   :media/source-generation
                                   :media/name
                                   :media/type
                                   :media/size
                                   :media/kind
                                   :media/container
                                   :media/format-version])]
          (if (= :datom (:media/container source))
            (media-result
              (assoc state
                     :converter/status :error
                     :converter/source source
                     :converter/output-name nil
                     :converter/error :already-datom
                     :converter/error-detail nil))
            (media-result
              (assoc state
                     :converter/status :ready
                     :converter/source source
                     :converter/output-name nil
                     :converter/error nil
                     :converter/error-detail nil))))

        :converter/selection-failed
        (media-result
          (assoc state
                 :converter/status :error
                 :converter/source nil
                 :converter/output-name nil
                 :converter/error
                 (or (:media/error event) :invalid-datom-media)
                 :converter/error-detail (:media/error-detail event)))

        :ui/converter-convert
        (if-let [source (:converter/source state)]
          (if (= :datom (:media/container source))
            (media-result state)
            (let [[next-state cmd]
                  (command-for-source
                    (assoc state
                           :converter/status :converting
                           :converter/output-name nil
                           :converter/error nil
                           :converter/error-detail nil)
                    source
                    :convert-source
                    {:media/duration-seconds nil})]
              (media-result next-state [cmd] [])))
          (media-result state))

        :converter/file-converted
        (if (stale-converter-event? state event)
          (media-result state)
          (media-result
            (assoc state
                   :converter/status :converted
                   :converter/output-name (:media/name event)
                   :converter/error nil
                   :converter/error-detail nil)))

        :converter/failed
        (if (stale-converter-event? state event)
          (media-result state)
          (media-result
            (assoc state
                   :converter/status :error
                   :converter/error
                   (or (:media/error event) :conversion-failed)
                   :converter/error-detail (:media/error-detail event))))

        :source-selected
        (if (stale-source-selection? state event)
          (media-result state)
          (let [source (select-keys event
                                    [:media/source-id
                                     :media/source-generation
                                     :media/name
                                     :media/type
                                     :media/size
                                     :media/kind
                                     :media/container
                                     :media/format-version])
                loaded (-> state
                           (assoc :player/status :loading
                                  :player/source source
                                  :player/media-kind
                                  (or (:media/kind event)
                                      (media-kind (:media/type event)))
                                  :player/duration-seconds 0.0
                                  :player/position-seconds 0.0
                                  :player/buffered []
                                  :player/seeking? false
                                  :player/error nil))
                [next-state cmd] (command loaded :load-source {})]
            (media-result next-state [cmd] [])))

        :source-closed
        (media-result
          (merge state
                 (select-keys initial-state
                              [:player/status :player/source
                               :player/media-kind :player/duration-seconds
                               :player/position-seconds :player/buffered
                               :player/seeking? :player/error])))

        :loaded-metadata
        (media-result
          (assoc state
                 :player/status :ready
                 :player/duration-seconds
                 (if (finite-number? (:media/duration-seconds event))
                   (double (:media/duration-seconds event))
                   0.0)
                 :player/video-width (:media/width event)
                 :player/video-height (:media/height event)
                 :player/error nil))

        :playing (media-result (assoc state
                                      :player/status :playing
                                      :player/error nil))
        :pause (media-result (assoc state :player/status :paused))
        :waiting (media-result (assoc state :player/status :waiting))
        :seeking (media-result (assoc state :player/seeking? true))
        :seeked (media-result (assoc state :player/seeking? false))
        :ended (media-result (assoc state :player/status :ended
                                   :player/seeking? false))

        :time
        (media-result
          (cond-> state
            (finite-number? (:media/position-seconds event))
            (assoc :player/position-seconds
                   (double (:media/position-seconds event)))
            (finite-number? (:media/duration-seconds event))
            (assoc :player/duration-seconds
                   (double (:media/duration-seconds event)))
            (vector? (:media/buffered event))
            (assoc :player/buffered (:media/buffered event))))

        :volume-change
        (let [next-state (cond-> state
                           (finite-number? (:media/volume event))
                           (assoc :player/volume
                                  (clamp (double (:media/volume event)) 0.0 1.0))
                           (boolean? (:media/muted? event))
                           (assoc :player/muted? (:media/muted? event)))]
          (media-result next-state [] [(settings-command next-state)]))

        :rate-change
        (let [next-state (if (and (finite-number? (:media/rate event))
                                  (pos? (:media/rate event)))
                           (assoc state :player/rate
                                  (double (:media/rate event)))
                           state)]
          (media-result next-state [] [(settings-command next-state)]))

        :fullscreen-change
        (media-result
          (assoc state :player/fullscreen? (boolean (:media/fullscreen? event))))

        :error
        (media-result
          (assoc state :player/status :error
                 :player/error (or (:media/error event) :media-error)))

        :command-failed
        (media-result
          (cond-> (assoc state :player/error (:media/error event))
            (= :play (:media.command/kind event))
            (assoc :player/status :paused)))

        :settings-loaded
        (media-result
          (merge state
                 (select-keys (:settings/value event)
                              [:player/volume :player/muted? :player/rate])))

        :ui/play
        (if-not (:player/source state)
          (media-result state)
          (let [[next-state cmd] (command state :play {})]
            (media-result next-state [cmd] [])))

        :ui/pause
        (if-not (:player/source state)
          (media-result state)
          (let [[next-state cmd] (command state :pause {})]
            (media-result next-state [cmd] [])))

        :ui/toggle-play
        (if-not (:player/source state)
          (media-result state)
          (let [kind (if (= :playing (:player/status state)) :pause :play)
                [next-state cmd] (command state kind {})]
            (media-result next-state [cmd] [])))

        :ui/seek
        (if-not (:player/source state)
          (media-result state)
          (let [duration (:player/duration-seconds state)
                requested (double (or (:media/position-seconds event) 0.0))
                position (clamp requested 0.0 (max 0.0 duration))
                [next-state cmd] (command
                                   state
                                   :seek
                                   {:media/position-seconds position})]
            (media-result next-state [cmd] [])))

        :ui/set-volume
        (let [[next-state cmd]
              (command state
                       :set-volume
                       {:media/volume
                        (clamp (double (or (:media/volume event) 0.0))
                               0.0
                               1.0)})]
          (media-result next-state [cmd] []))

        :ui/toggle-muted
        (let [[next-state cmd]
              (command state :set-muted
                       {:media/muted? (not (:player/muted? state))})]
          (media-result next-state [cmd] []))

        :ui/set-rate
        (let [rate (double (or (:media/rate event) 1.0))
              [next-state cmd] (command state :set-rate
                                        {:media/rate (clamp rate 0.25 4.0)})]
          (media-result next-state [cmd] []))

        :ui/convert
        (if-not (:player/source state)
          (media-result state)
          (let [[next-state cmd]
                (command state
                         :convert-source
                         {:media/duration-seconds
                          (:player/duration-seconds state)})]
            (media-result next-state [cmd] [])))

        :ui/toggle-fullscreen
        (let [command-kind (if (:player/fullscreen? state)
                             :exit-fullscreen
                             :request-fullscreen)
              [next-state cmd] (command state command-kind {})]
          (media-result next-state [cmd] []))

        (media-result state)))))


(defn transition-ast
  "Compile a controller invocation with Yang. State and event are literal
   immutable values embedded in the resulting Universal AST."
  [state event]
  (yang/compile-form (list 'media-transition state event)))


(defn- run-with
  [create-vm state event]
  (-> (create-vm {:env {'media-transition transition}})
      (vm/eval (transition-ast state event))
      (vm/value)))


(defn run-transition
  "Production controller boundary: Yang -> Universal AST -> register Yin.VM."
  [state event]
  (run-with register/create-vm state event))


(defn run-transition-all-vms
  [state event]
  {:ast-walker (run-with ast-walker/create-vm state event)
   :stack (run-with stack/create-vm state event)
   :register (run-with register/create-vm state event)})
