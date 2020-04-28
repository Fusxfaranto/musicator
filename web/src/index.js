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
}
const midiNoteToY = midiNote => {
    return (127 - midiNote) * keyScale;
}
const gridStart = () => {
    return keyWidth;
}

const gridNoteRadius = 7;

const GridNote = props => {
    return (
        <Circle
          x={props.x}
          y={props.y}
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
          fill='#888822'
          />);
}

const GridItem = props => {
    assert(props.progEvents.length >= 1);

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
              key={["GridNote", props.progId, e.midi_note, e.at_time]}
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
}

const Foo = props => {
    const [state, setState] = useState({
        x: 200,
        y: 200
    });

    const [dragging, setDragging] = useState(false);

    return (
        <Circle
          x={state.x}
          y={state.y}
          radius={10}
          draggable={true}
          fill={dragging ? 'green' : 'red'}
          onDragStart={() => {
              setDragging(true);
          }}
          onDragEnd={e => {
              console.log(e.target.x(), e.target.y());
              // setState({
              //     x: e.target.x(),
              //     y: e.target.y()
              // });
              setDragging(false);
          }}
          // onDragMove={e => {
          //     //console.log(e);
          // }}
          dragBoundFunc={pos => {
              //console.log(pos);

              let x = Math.round(pos.x / 50.0) * 50;
              let y = Math.round(pos.y / 50.0) * 50;
              return {
                  x: Math.clamp(x, 0, props.stageWidth),
                  y: Math.clamp(y, 0, props.stageHeight),
              };
          }}
          />);
};

const keyIsWhite = midiNote => {
    const rel_note = (midiNote + (128 * 12) - 72) % 12;
    return rel_note !== 1 && rel_note !== 3 && rel_note !== 6 && rel_note !== 8 && rel_note !== 10;
}
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
}

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
              // TODO ??
              key={i}
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

const Chart = props => {
    {
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
    }

    // TODO
    const stageW = 3000;
    const stageH = 2400;

    const tempoSecs = props.state.tempo / 60.0;
    const beatSpacing = timeToX(1 / tempoSecs);

    let stageElems = [];
    stageElems.push(
        <Grid
          width={stageW}
          height={stageH}
          dir={GridDir.v}
          span={beatSpacing / props.state.snap_denominator}
          key='grid_v_sub'
          color='#333333'
          />);
    stageElems.push(
        <Grid
          width={stageW}
          height={stageH}
          dir={GridDir.v}
          span={beatSpacing}
          key='grid_v'
          color='gray'
          />);
    stageElems.push(
        <Grid
          width={stageW}
          height={stageH}
          dir={GridDir.h}
          span={keyScale}
          key='grid_h'
          color='gray'
          />);
    stageElems.push(
        <Foo
          stageWidth={stageW}
          stageHeight={stageH}
          key='foo'
          />);

    let gridItems = [];
    for (let i = 0; i < props.state.progs.length; i++) {
        const prog = props.state.progs[i];
        // TODO should be derived from prog
        const numChannels = 128;
        let channelEvents = [...Array(numChannels)].map(a => []);
        for (let j = 0; j < prog.track_events.length; j++) {
            let e = prog.track_events[j];
            switch (e.type) {
            case 'ON':
                assert(channelEvents[e.midi_note].length === 0);
                channelEvents[e.midi_note].push(e);
                break;
            case 'OFF':
                assert(channelEvents[e.midi_note].length > 0);
                channelEvents[e.midi_note].push(e);
                gridItems.push(
                    <GridItem
                      progId={i}
                      progEvents={channelEvents[e.midi_note]}
                      key={['GridItem', channelEvents[e.midi_note][0].at_time, i]}
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

    return (
        <div
          className="chart-container"
          >
          { //!skipStage &&
                  <Stage
                        width={stageW} height={stageH}
                        >
                        <Layer>
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
}

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
}

const App = props => {
    const [state, setState] = useState({
        progs: [],
    });

    const [shouldUpdate, setShouldUpdate] = useState(false);

    const ws = props.ws;
    ws.onopen = () => {
        console.log('websocket connected');

        ws.send(JSON.stringify({
            type: "getstate",
            contents: null,
        }));
    }

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
    }

    ws.onclose = () => {
        console.log('websocket disconnected');
    }

    let progs = state.progs;

    const setProgContents = (i, contents) => {
        //console.log(i);
        //console.log(contents);

        if (progs[i].prog !== contents) {
            progs[i].prog = contents;
            setState({
                ...state,
                progs: progs,
            })

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

        ws.send(JSON.stringify(
            {
                type: "setstate",
                contents: state,
            }
        ));

        setShouldUpdate(false);
    }, [shouldUpdate, state, ws]);

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
                    })
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
                      ));}
                  }>
                  Play
                </button>

                <br />
                <br />

                <NumInput
                  stateVal={state.snap_denominator}
                  updateState={(value) => {
                      setState({
                          ...state,
                          snap_denominator: value,
                      })
                      setShouldUpdate(true);
                  }}
                  />
                  <NumInput
                    stateVal={state.tempo}
                    updateState={(value) => {
                        setState({
                            ...state,
                            tempo: value,
                        })
                        setShouldUpdate(true);
                    }}
                    />
            </div>
            <Chart
              state={state}
              />
          </div>
        </div>
    );
};

const ws = new WebSocket('ws://127.0.0.1:3001');
render(<App ws={ws} />, document.getElementById('root'));
