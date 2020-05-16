// -*- mode: js-jsx -*-

import AceEditor from "react-ace-builds";
import React, { useRef, useEffect, useState } from 'react';
//import Konva from 'konva';
import { render } from 'react-dom';
import { Circle, Stage, Layer, Line, Rect } from 'react-konva';


import 'ace-builds/src-noconflict/mode-c_cpp';
import 'ace-builds/src-noconflict/theme-github';

import './index.css';


Math.clamp = function(number, min, max) {
    return Math.max(min, Math.min(number, max));
};

const assert = b => {
    if (b) {
    } else {
        throw new Error("assert");
    }
};

// TODO note input by simultaneously tapping out beat and playing notes, with configurable snap intervals (which will require having tempo integration)

const keyScale = 15;
const keyWidth = 60;

const timeToX = time => {
    return time * 500;
};
const xToTime = x => {
    return x / 500;
};
const midiNoteToY = midiNote => {
    return (127 - midiNote) * keyScale;
};
const yToMidiNote = y => {
    return 127 - (y / keyScale);
};
const gridStart = () => {
    return keyWidth;
};

const gridNoteRadius = 7;


const GridNote = props => {
    let draggable;
    let dragBoundFunc = null;
    //let onDragStart = null;
    let onDragEnd = null;

    let time = xToTime(props.x);
    let midiNote = yToMidiNote(props.y);
    assert(midiNote === Math.round(midiNote));

    switch (props.noteType) {
    case 'ON':
        draggable = true;
        dragBoundFunc = pos => {
            //console.log(pos);
            const snap = (v, b, s) => {
                return Math.round((v - s) / b) * b + s;
            };
            let x = snap(pos.x, props.stageProps.beatSubSpacing, gridStart());
            let y = snap(pos.y, keyScale, 0);
            return {
                x: Math.clamp(x, gridStart(), props.stageProps.width),
                y: Math.clamp(y, 0, props.stageProps.height),
            };
        };

        onDragEnd = e => {
            let x = e.target.x();
            let y = e.target.y();

            if (x !== props.x || y !== props.y) {
                props.shiftEvents(xToTime(x) - time, yToMidiNote(y) - midiNote);
            }

            //setDragging(false);
        };
        break;

    case 'OFF':
        draggable = false;
        break;

    default:
        assert(0);
    }


    return (
        <Circle
          x={props.x}
          y={props.y}
          draggable={draggable}
          dragBoundFunc={dragBoundFunc}
          onDragEnd={onDragEnd}
          radius={gridNoteRadius}
          fill='#eeee22'
          />);
};

const GridNoteConnector = props => {
    return (
        <Rect
          x={props.x}
          y={props.y - gridNoteRadius}
          width={props.width}
          height={gridNoteRadius * 2}
          fill='#aaaa22'
          />);
};

const GridItem = props => {
    assert(props.progEvents.length >= 1);

    let shiftEvents = (time, midiNote) => {
        let es = props.progEvents;
        const esBackupStr = JSON.stringify(es);
        console.log(es);
        console.log(time);
        console.log(midiNote);
        for (let i = 0; i < es.length; i++) {
            es[i].at_time += time;
            es[i].midi_note += midiNote;
            assert(es[i].at_time >= 0);
            assert(es[i].midi_note >= 0);
            assert(es[i].midi_note < 128);
        }

        props.updateEvents();
    };

    let items = [];
    let firstX = undefined;
    let lastX = undefined;
    let lastY = undefined;
    for (let i = 0; i < props.progEvents.length; i++) {
        let e = props.progEvents[i];

        // TODO
        const x = timeToX(e.at_time) + gridStart();
        const y = midiNoteToY(e.midi_note);

        if (i === 0) {
            firstX = x;
        }

        if (lastY !== y) {
            if (lastY !== undefined) {
                // TODO
                console.error("inconsistent y");
            }
            lastY = y;
        }
        lastX = x;

        items.push(
            <GridNote
              x={x}
              y={y}
              noteType={e.type}
              key={["GridNote", props.progId, e.midi_note, e.at_time]}
              stageProps={props.stageProps}
              shiftEvents={shiftEvents}
              />);
    }

    items.push(
        <GridNoteConnector
          x={firstX}
          y={lastY}
          width={lastX - firstX}
          key={["GridNoteConnector", props.progId, props.progEvents[0].midi_note, props.progEvents[0].at_time]}
          />);

    return (
        <>
          {items.reverse()}
        </>
    );
};

const keyIsWhite = midiNote => {
    const rel_note = (midiNote + (128 * 12) - 72) % 12;
    return rel_note !== 1 && rel_note !== 3 && rel_note !== 6 && rel_note !== 8 && rel_note !== 10;
};
const GridKeyVisual = props => {
    const fill = keyIsWhite(props.midiNote) ? 'white' : 'black';

    return (
        <Rect
          x={0}
          y={midiNoteToY(props.midiNote)}
          width={keyWidth}
          height={keyScale}
          fill={fill}
          stroke="gray"
          />
    );
};

const GridDir = Object.freeze({
    v: Symbol("GridDir.v"),
    h: Symbol("GridDir.h"),
});

const Grid = props => {
    let elems = [];
    let to = (() => {
        switch (props.dir) {
        case GridDir.v:
            return props.width;
        case GridDir.h:
            return props.height;
        default:
            return null;
        }
    })();
    for (let i = 0; i < to; i += props.span) {
        let points = (() => {
            switch (props.dir) {
            case GridDir.v:
                return [i + gridStart(), 0, i + gridStart(), props.height];
            case GridDir.h:
                return [0, i, props.width, i];
            default:
                return null;
            }
        })();
        elems.push(
            <Line
              points={points}
              stroke={props.color}
              strokeWidth={1}
              key={['Grid Line', i, props]}
              />);
    }

    for (let i = 0; i < 128; i++) {
        elems.push(
            <GridKeyVisual
              midiNote={i}
              key={['GridKeyVisual', i]}
              />);
    }

    return (
        <>
          {elems}
        </>
    );
};

const genChannelEventsMap = (prog) => {
    // TODO should be derived from prog
    const numChannels = 128;
    return [...Array(numChannels)].map(a => []);
};

const genGridItems = (progs, stageProps, updateField) => {
    let gridItems = [];
    for (let i = 0; i < progs.length; i++) {
        const prog = progs[i];
        let channelEvents = genChannelEventsMap(prog);
        for (let j = 0; j < prog.track_events.length; j++) {
            let e = prog.track_events[j];
            switch (e.type) {
            case 'ON':
                if (channelEvents[e.midi_note].length !== 0) {
                    console.log(channelEvents);
                    console.log(e);
                    assert(0);
                }
                channelEvents[e.midi_note].push(e);
                break;
            case 'OFF':
                assert(channelEvents[e.midi_note].length > 0);
                channelEvents[e.midi_note].push(e);
                const updateEvents = () => {
                    prog.track_events.sort((a, b) => {return a.at_time - b.at_time;});
                    updateField(["progs", i, "track_events"]);
                };
                gridItems.push(
                    <GridItem
                      progId={i}
                      progEvents={channelEvents[e.midi_note]}
                      key={['GridItem', channelEvents[e.midi_note][0].id]}
                      stageProps={stageProps}
                      updateEvents={updateEvents}
                      />);
                channelEvents[e.midi_note] = [];
                break;
            default:
                throw new Error("");
            }
            //console.log(prog.track_events[j]);
        }
        //console.log(channelEvents);
    }

    return gridItems;
};

const Chart = props => {
    // const ref = useRef();
    // const [dim, setDim] = useState({
    //     width: 0,
    //     height: 0,
    // });
    // const [skipStage, setSkipStage] = useState(true);

    // const autoSetDim = () => {
    //     if (ref.current) {
    //         setDim({
    //             width: ref.current.offsetWidth,
    //             height: ref.current.offsetHeight,
    //         });
    //     }
    // };

    // useEffect(() => {
    //     autoSetDim();
    //     setSkipStage(false);
    // }, []);

    // useEffect(() => {
    //     let resize_timer = null;
    //     const handler = () => {
    //         clearInterval(resize_timer);
    //         autoSetDim();
    //         setSkipStage(true);
    //         resize_timer = setTimeout(() => { setSkipStage(false); }, 200);
    //     };

    //     window.addEventListener('resize', handler);

    //     return () => window.removeEventListener('resize', handler);
    // }, []);
    // const stageW = dim.width;// - 100;
    // const stageH = dim.height;// - 100;

    const tempoSecs = props.state.tempo / 60.0;
    // TODO
    let stageProps = {
        width: 3000,
        height: 2400,
        beatSpacing: timeToX(1 / tempoSecs),
    };
    stageProps.beatSubSpacing = stageProps.beatSpacing / props.state.snap_denominator;

    let stageElems = [];
    stageElems.push(
        <Grid
          width={stageProps.width}
          height={stageProps.height}
          dir={GridDir.v}
          span={stageProps.beatSubSpacing}
          key='grid_v_sub'
          color='#333333'
          />);
    stageElems.push(
        <Grid
          width={stageProps.width}
          height={stageProps.height}
          dir={GridDir.v}
          span={stageProps.beatSpacing}
          key='grid_v'
          color='gray'
          />);
    stageElems.push(
        <Grid
          width={stageProps.width}
          height={stageProps.height}
          dir={GridDir.h}
          span={keyScale}
          key='grid_h'
          color='gray'
          />);

    const cursorPos = timeToX(props.state.cursor) + gridStart();
    stageElems.push(
        <Line
          points={[cursorPos, 0, cursorPos, stageProps.height]}
          stroke='red'
          strokeWidth={2}
          key={['cursor']}
          />);

    let gridItems = genGridItems(props.state.progs, stageProps, props.ops.updateField);

    return (
        <div
          className="chart-container"
          >
          { //!skipStage &&
                  <Stage
                        width={stageProps.width} height={stageProps.height}
                        >
                        <Layer
                              onMouseDown={e => {
                                  console.log(e.target);
                              }}
                              >
                              <Rect width={stageProps.width} height={stageProps.height} />
                                  {stageElems}
                                  {gridItems}
                            </Layer>
                      </Stage>
                  }
        </div>
    );
};


const ProgMenuEntry = props => {
    //const [hideVars, setHideVars] = useState(false);
    const hideVars = props.hideVars;

    const arrow = hideVars ? '>' : 'V';

    const prog = props.prog;

    const varsList = hideVars ? null :
          <ul className="prog-menu-list">
          {prog.locals.map((local =>
                            <li key={local.name}> {local.name} {local.type} </li>
                           ))}
    </ul>;
    
    return (
        <>
          <li>
            <div onClick={props.onClick}>
              {arrow}
              &nbsp;
              {prog.name}
            </div>

            {varsList}
          </li>
        </>
    );
};

const CodeInput = props => {
    return (
        <AceEditor
          className={props.className}
          mode="c_cpp"
          theme="github"
          value={props.contents}
          onChange={props.onChange}
          name={props.name}
          // editorProps={{ $blockScrolling: true }}
          />);
};

const ProgInput = props => {
    return (
        <CodeInput
          className="prog-menu-input"
          contents={props.unselected ? "" : props.contents}
          onChange={props.onChange}
          name={props.name}
          />
    );
};

const ProgMenu = props => {
    const [showIdx, setShowIdx] = useState(-1);

    const noneSelected = showIdx === -1;
    const selectedProg = noneSelected ? null : props.progs[showIdx];
    const selectedContents = noneSelected ? null : selectedProg.prog;
    //console.log(selectedContents);

    const handleChangeTo = (i) => () => {
        if (i !== showIdx) {
            setShowIdx(i);
        } else {
            setShowIdx(-1);
        }
    };
    
    return (
        <>

          <ProgInput
            name="main-prog-input"
            contents={selectedContents}
            unselected={noneSelected}
            onChange={(value) => {
                if (noneSelected) {
                    //setProgInputContents("");
                } else {
                    //setProgInputContents(value);
                    props.setProgContents(showIdx, value);
                }
            }}
            />

            <ul className="prog-menu-list">
              {props.progs.map(
                  ((prog, i) =>
                   <ProgMenuEntry
                         prog={prog}
                         key={prog.name}
                         hideVars={i !== showIdx}
                         onClick={handleChangeTo(i)}
                         />)
              )}
        </ul>
            </>
    );
};

const NumInput = props => {
    const [inputState, setInputState] = useState(null);

    if (props.stateVal !== undefined && inputState === null) {
        setInputState(props.stateVal);
    }

    useEffect(() => {
        // reset when reloading
        if (props.stateVal !== undefined && props.stateVal !== inputState) {
            setInputState(props.stateVal);
        }
    }, [inputState, props.stateVal]);

    //console.log('asdf', props.stateVal, inputState);
    return (
        <input
          type="number"
          value={inputState === null ? '' : inputState}
          onChange={(e) => {
              const value = e.currentTarget.value;
              //console.log(value);
              setInputState(value);
              if (value > 0) {
                  props.updateState(parseInt(value));
              }
              //return value;
          }}
          />
    );
};

const App = props => {
    const [state, setState] = useState({
        progs: [],
    });

    // const maxStateHistory = 20;
    // const [stateHistory, setStateHistory] = useState({
    //     nextIdx: 0,
    //     states: [],
    // });

    // const state = stateHistory.states.length > 0 ? stateHistory.states[stateHistory.nextIdx - 1] : {
    //     progs: [],
    // };
    // const setState = (s) => {
    //     let sh = {...stateHistory};
    //     sh.nextIdx++;
    //     sh.states.push(s);
    //     setStateHistory(sh);
    //     console.log("stateHistory ", sh);
    // };

    const [shouldUpdate, setShouldUpdate] = useState(false);

    const ws = props.ws;
    ws.onopen = () => {
        console.log('websocket connected');

        ws.send(JSON.stringify({
            type: "getstate",
            contents: null,
        }));
    };

    ws.onmessage = evt => {
        const message = JSON.parse(evt.data);
        console.log(message);

        switch (message.type) {
        case 'set':
            setState(message.contents);
            break;

        default:
            console.error("bad message type");
        }
    };

    ws.onclose = () => {
        console.log('websocket disconnected');
    };

    console.log("state: ", state);
    let progs = state.progs;

    const setProgContents = (i, contents) => {
        //console.log(i);
        //console.log(contents);

        if (progs[i].prog !== contents) {
            progs[i].prog = contents;
            setState({
                ...state,
                progs: progs,
            });

            setShouldUpdate(true);
        } else {
            console.error("???");
        }
    };

    useEffect(() => {
        // TODO something more efficient
        if (!shouldUpdate) {
            return;
        }

        console.log("sending state");
        ws.send(JSON.stringify(
            {
                type: "setstate",
                contents: state,
            }
        ));

        setShouldUpdate(false);
    }, [
        shouldUpdate,
        state,
        //stateHistory,
        ws,
    ]);


    const ops = {
        // TODO since javascript hates immutability, does this
        // even make sense to have?  (if it does, it'll probably
        // only be for incremental updates)
        updateField: (accessors) => {
            let s = state;
            for (let i = 0; i < accessors.length; i++) {
                s = s[accessors[i]];
            }
            setState({...state});
            setShouldUpdate(true);
        },

        undo: () => {

        },
    };

    return (
        <div className="app-container">
          <div className="menu-container">
            <ProgMenu
              progs={progs}
              setProgContents={setProgContents}
              />
          </div>
          <div className="app-side-container">
            <div className="other-container">

              <CodeInput
                className="prog-helper-input"
                contents={state.prog_helpers}
                onChange={(value) => {
                    setState({
                        ...state,
                        prog_helpers: value,
                    });
                    setShouldUpdate(true);
                }}
                />

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "save",
                              contents: {
                                  // TODO
                                  filename: "state.json",
                              },
                          }
                      ));}
                  }>
                  Save
                </button>

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "load",
                              contents: {
                                  // TODO
                                  filename: "state.json",
                              },
                          }
                      ));}
                  }>
                  Load
                </button>

                <br />
                <br />

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "pause",
                              contents: null,
                          }
                      ));}
                  }>
                  Pause
                </button>

                <button onClick={() => {
                      ws.send(JSON.stringify(
                          {
                              type: "play",
                              contents: null,
                          }
                      ));
                      ws.send(JSON.stringify(
                          {
                              type: "getstate",
                              contents: null,
                          }
                      ));
                      }
                  }>
                  Play
                </button>

                <button onClick={() => {
                      state.cursor = 0;
                      ops.updateField(["cursor"]);
                  }}>
                  Zero
                </button>

                <br />
                <br />

                <NumInput
                  stateVal={state.snap_denominator}
                  updateState={(value) => {
                      setState({
                          ...state,
                          snap_denominator: value,
                      });
                      setShouldUpdate(true);
                  }}
                  />
                  <NumInput
                    stateVal={state.tempo}
                    updateState={(value) => {
                        setState({
                            ...state,
                            tempo: value,
                        });
                        setShouldUpdate(true);
                    }}
                    />
            </div>
            <Chart
              state={state}
              ops={ops}
              />
          </div>
        </div>
    );
};

const ws = new WebSocket('ws://127.0.0.1:3001');
render(<App ws={ws} />, document.getElementById('root'));
