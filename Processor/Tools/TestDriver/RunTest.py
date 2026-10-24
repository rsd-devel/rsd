# -*- coding: utf-8 -*-

# A helper script for test RSD using QuestaSim/Verilator/VivadoSim.
# It runs test programs and verify results

import os, sys, subprocess
import re
import shlex
from optparse import OptionParser
from xml.etree import ElementTree

CFG_XML_FILE_NAME = 'cfg.xml'
REG_OUT_FILE_NAME = 'reg.out.hex'
SERIAL_OUT_FILE_NAME = 'serial.out.txt'
SERIAL_REF_FILE_NAME = 'serial.ref.txt'

# Warning! : vsim cannot use abspath as command line argument
QUESTASIM_PROJECT_DIR_PATH = os.path.relpath(
    os.path.join( os.path.dirname( __file__ ), '../../Project/ModelSim' )
)

VERILATED_FILE_NAME = os.path.relpath(
    os.path.join( os.path.dirname( __file__ ), '../../Project/Verilator/obj_dir/VTestMain' )
)

VIVADOSIM_PROJECT_DIR_PATH = os.path.relpath(
    os.path.join( os.path.dirname( __file__ ), '../../Project/VivadoSim/work' )
)


class TestConfigError(Exception):
    """ Exception class """
    pass

class SimulationError(Exception):
    """The simulator could not start or exited unsuccessfully."""
    pass


def RunSimulationCommand(command, logPath, omitStdout, omitPrintCommand, cwd=None):
    # Capture the simulator's status directly; a shell pipeline reports tee's status.
    if not omitPrintCommand:
        displayCommand = " ".join(shlex.quote(arg) for arg in command)
        if cwd is not None:
            displayCommand = "cd %s && %s" % (shlex.quote(cwd), displayCommand)
        print(displayCommand, flush=True)

    logFilePath = os.path.join(cwd, logPath) if cwd is not None else logPath
    try:
        with open(logFilePath, 'wb') as logFile:
            with subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT) as process:
                for chunk in iter(lambda: process.stdout.read1(65536), b''):
                    logFile.write(chunk)
                    if not omitStdout:
                        sys.stdout.buffer.write(chunk)
                        sys.stdout.buffer.flush()
                returnCode = process.wait()
    except OSError as error:
        raise SimulationError("Cannot run %s: %s (log: %s)" %
                              (command[0], error, logFilePath)) from error

    if returnCode != 0:
        try:
            reason = ' (%s)' % ReadSimulationResult(logFilePath)
        except SimulationError:
            reason = ''
        raise SimulationError("%s exited with status %d%s (log: %s)" %
                              (command[0], returnCode, reason, logFilePath))


class ConfigParser( object ):
    """ Parse a test configuration XML file. """

    # Const
    REG_NUMS = {
        'R0' :0,   'r0' :0,
        'R1' :1,   'r1' :1,
        'R2' :2,   'r2' :2,
        'R3' :3,   'r3' :3,
        'R4' :4,   'r4' :4,
        'R5' :5,   'r5' :5,
        'R6' :6,   'r6' :6,
        'R7' :7,   'r7' :7,
        'R8' :8,   'r8' :8,
        'R9' :9,   'r9' :9,
        'R10':10,  'r10':10,
        'R11':11,  'r11':11,
        'R12':12,  'r12':12,
        'R13':13,  'r13':13,
        'R14':14,  'r14':14,
        'R15':15,  'r15':15,
        'R16':16,  'r16':16,
        'R17':17,  'r17':17,
        'R18':18,  'r18':18,
        'R19':19,  'r19':19,
        'R20':20,  'r20':20,
        'R21':21,  'r21':21,
        'R22':22,  'r22':22,
        'R23':23,  'r23':23,
        'R24':24,  'r24':24,
        'R25':25,  'r25':25,
        'R26':26,  'r26':26,
        'R27':27,  'r27':27,
        'R28':28,  'r28':28,
        'R29':29,  'r29':29,
        'R30':30,  'r30':30,
        'R31':31,  'r31':31,
        'PC':32,
        'f0':33,
        'f1':34,
        'f2':35,
        'f3':36,
        'f4':37,
        'f5':38,
        'f6':39,
        'f7':40,
        'f8':41,
        'f9':42,
        'f10':43,
        'f11':44,
        'f12':45,
        'f13':46,
        'f14':47,
        'f15':48,
        'f16':49,
        'f17':50,
        'f18':51,
        'f19':52,
        'f20':53,
        'f21':54,
        'f22':55,
        'f23':56,
        'f24':57,
        'f25':58,
        'f26':59,
        'f27':60,
        'f28':61,
        'f29':62,
        'f30':63,
        'f31':64
        }

    def __init__( self ):
        self.maxTestCycles = None
        self.registerValueDict = {}

    def Parse( self, xmlFileName ):
        # Parse XML File
        self.xmlFileName = xmlFileName
        tree = ElementTree.parse( xmlFileName )

        def readInteger(name, default, minimum=0):
            text = tree.findtext('./' + name)
            try:
                value = default if text is None else int(text)
            except ValueError:
                raise TestConfigError('%s must be an integer in %s' % (name, xmlFileName))
            if not minimum <= value <= 2**63 - 1:
                raise TestConfigError('%s is out of range in %s' % (name, xmlFileName))
            return value

        # A zero total budget disables that limit. Retain cycle-only settings
        # for external tests until their configurations are migrated.
        self.maxTestInstructions = readInteger('MaxTestInstructions', 0)
        self.maxTestCycles = readInteger('MaxTestCycles', 0)
        self.maxNoCommitCycles = readInteger('MaxNoCommitCycles', 500, minimum=1)
        if self.maxTestInstructions == 0 and self.maxTestCycles == 0:
            raise TestConfigError('A positive MaxTestInstructions or MaxTestCycles is required in %s' % xmlFileName)
        self.enablePC_Goal = readInteger('EnablePC_Goal', 1)
        if self.enablePC_Goal not in (0, 1):
            raise TestConfigError('EnablePC_Goal must be 0 or 1 in %s' % xmlFileName)

        # Set reference register values.
        elemRegisterValues = tree.find('./RegisterValues')
        if ( elemRegisterValues is None ):
            raise TestConfigError( 'Element "./RegisterValues" is not found in %s' % xmlFileName )

        for elem in elemRegisterValues:
            regNum = self.REG_NUMS[ elem.tag ]
            regValue = int( elem.text.lstrip().rstrip(), 0 )
            self.registerValueDict[regNum] = regValue

    def GetSimulationParameters(self):
        return [
            ('MAX_TEST_INSTRUCTIONS', self.maxTestInstructions),
            ('MAX_NO_COMMIT_CYCLES', self.maxNoCommitCycles),
            ('MAX_TEST_CYCLES', self.maxTestCycles),
            ('ENABLE_PC_GOAL', self.enablePC_Goal),
        ]


def ReadSimulationResult(logPath):
    try:
        with open(logPath, errors='replace') as log:
            contents = log.read()
    except OSError as error:
        raise SimulationError('Cannot read simulation result: %s (log: %s)' % (error, logPath)) from error
    reasons = re.findall(r'^(?:#\s*)?Simulation result: (\w+)\s*$', contents, re.MULTILINE)
    if len(reasons) != 1:
        raise SimulationError('Missing or ambiguous simulation result; rebuild the simulator (log: %s)' % logPath)
    return reasons[0]


def CheckSimulationResult(config, logPath):
    # Check the reason independently of the process status: simulator frontends
    # do not all propagate $fatal in the same way. Also reject stale models
    # which do not implement the requested progress limits.
    reason = ReadSimulationResult(logPath)
    if config.enablePC_Goal:
        expected = 'pc_goal'
    elif config.maxTestInstructions:
        expected = 'instruction_limit'
    else:
        expected = 'cycle_limit'
    if reason != expected:
        raise SimulationError('Simulation stopped with %s; expected %s (log: %s)' %
                              (reason, expected, logPath))
    return reason


class SimulationDriver( object ):
    LIBRARY_NAME = 'Main'
    TOP_MODULE_NAME = 'TestMain'
    VSIM_LOG_FILE_NAME = 'vsim.log'

    def __init__(self, projectDirPath, testCodeDirPath, config, options):
        self.projectDirPath = projectDirPath   # A project directory for QuestaSim
        self.testCodeDirPath = testCodeDirPath # A directory where test code exists

        self.vsimLogPath = os.path.join(testCodeDirPath, self.VSIM_LOG_FILE_NAME)

        self.additionalOptionList = ['+%s=%d' % parameter for parameter in config.GetSimulationParameters()]
        if options.rsdLogFileName is not None:
            self.additionalOptionList.append("+RSD_LOG_FILE=%s" % (options.rsdLogFileName))
        self.omitStdout = options.omitQuestasimMessage
        self.omitPrintCommand = options.quietMode

    # Perform simulation
    def RunSimulation(self):
        QUESTASIM_DIR_PATH = os.environ['RSD_QUESTASIM_PATH']
        cmd = [
            os.path.join(QUESTASIM_DIR_PATH, 'vsim'), '-c', '+SEED=0',
            '%s/%s.%s' % (self.projectDirPath, self.LIBRARY_NAME, self.TOP_MODULE_NAME),
            '+TEST_CODE=%s' % self.testCodeDirPath,
        ] + self.additionalOptionList + ['-do', 'run -all']
        RunSimulationCommand(cmd, self.vsimLogPath, self.omitStdout, self.omitPrintCommand)

    def GetLogPath(self):
        return self.vsimLogPath


class VerilatorSimulationDriver(object):
    VERILATOR_LOG_FILE_NAME = 'verilator.log'

    def __init__(self, verilatedBinPath, testCodeDirPath, config, options):
        self.verilatedBinPath = verilatedBinPath    # A path to a verilated binary 
        self.testCodeDirPath = testCodeDirPath      # A directory where test code exists
        self.verilatorLogPath = os.path.join(testCodeDirPath, self.VERILATOR_LOG_FILE_NAME)

        self.additionalOptionList = []
        self.additionalOptionList.append("+TEST_CODE=%s" % (testCodeDirPath))
        self.additionalOptionList.extend('+%s=%d' % parameter for parameter in config.GetSimulationParameters())
        if options.rsdLogFileName is not None:
            self.additionalOptionList.append("+RSD_LOG_FILE=%s" % (options.rsdLogFileName))
        self.omitStdout = options.omitQuestasimMessage
        self.omitPrintCommand = options.quietMode

    # シミュレーションを実行
    def RunSimulation(self):
        cmd = [self.verilatedBinPath] + self.additionalOptionList
        RunSimulationCommand(cmd, self.verilatorLogPath, self.omitStdout, self.omitPrintCommand)

    def GetLogPath(self):
        return self.verilatorLogPath


class VivadoSimulationDriver(object):
    TOP_MODULE_NAME    = 'TestMain'
    XSIM_LOG_FILE_NAME = 'xsim.log'
    XELAB_LOG_FILE_NAME = 'xelab.log'
    SOURCE_ROOT        = '../../../Src/'

    def __init__(self, projectDirPath, testCodeDirPath, config, options):
        self.projectDirPath  = projectDirPath   # Vivado Simulation project directory
        self.testCodeDirPath = testCodeDirPath  # Test code directory
        self.xsimLogPath     = self.SOURCE_ROOT + os.path.join(testCodeDirPath, self.XSIM_LOG_FILE_NAME)
        self.xelabLogPath     = self.SOURCE_ROOT + os.path.join(testCodeDirPath, self.XELAB_LOG_FILE_NAME)
        self.xsimPath = os.environ['RSD_VIVADO_BIN'] + '/xsim'
        self.xelabPath = os.environ['RSD_VIVADO_BIN'] + '/xelab'
        self.testID = testCodeDirPath.replace("/", "-") # Make test id from testCodeDirPath

        self.additionalOptionList = []
        for parameter in config.GetSimulationParameters():
            self.additionalOptionList.extend(['-testplusarg', '%s=%d' % parameter])
        self.additionalOptionList.extend(['-testplusarg', 'TEST_CODE=%s' % (self.SOURCE_ROOT + testCodeDirPath)])
        self.additionalOptionList.extend(['-testplusarg', 'DUMMY_DATA_FILE=%s' % (self.SOURCE_ROOT + 'Verification/DummyData.hex')])
        self.omitStdout = options.omitQuestasimMessage
        self.omitPrintCommand = options.quietMode


    # Run simulation
    def RunSimulation(self):
        cmd = [self.xelabPath, '-relax', '-s', self.testID, self.TOP_MODULE_NAME]
        RunSimulationCommand(cmd, self.xelabLogPath, self.omitStdout,
                             self.omitPrintCommand, cwd=self.projectDirPath)

        cmd = [self.xsimPath, '-runall'] + self.additionalOptionList + [self.testID]
        RunSimulationCommand(cmd, self.xsimLogPath, self.omitStdout,
                             self.omitPrintCommand, cwd=self.projectDirPath)

    def GetLogPath(self):
        return os.path.normpath(os.path.join(self.projectDirPath, self.xsimLogPath))


class PostSynthesisSimulationDriver(VivadoSimulationDriver):
    SOURCE_ROOT = ''

    def __init__(self, projectDirPath, config, options):
        super().__init__(projectDirPath, '.', config, options)

    def RunSimulation(self):
        # Make compiles the netlist and testbench into this XSim snapshot.
        cmd = [self.xsimPath, 'post_synthesis', '-runall', '-nolog', '-onerror', 'quit',
               '-testplusarg', 'SHOW_SERIAL_OUT=1'] + self.additionalOptionList
        RunSimulationCommand(cmd, self.xsimLogPath, self.omitStdout,
                             self.omitPrintCommand, cwd=self.projectDirPath)


class VCSPostSynthesisSimulationDriver(SimulationDriver):
    VSIM_LOG_FILE_NAME = 'vcs.log'

    def __init__(self, projectDirPath, config, options):
        super().__init__(projectDirPath, '.', config, options)

    def RunSimulation(self):
        cmd = ['./simv', '+TEST_CODE=.', '+SHOW_SERIAL_OUT=1'] + self.additionalOptionList
        RunSimulationCommand(cmd, self.vsimLogPath, self.omitStdout,
                             self.omitPrintCommand, cwd=self.projectDirPath)
        # VCS can report timing violations without returning a failing status.
        with open(self.GetLogPath(), errors='replace') as log:
            if re.search(r'Timing violation', log.read(), re.IGNORECASE):
                raise SimulationError('Timing violation (log: %s)' % self.GetLogPath())

    def GetLogPath(self):
        return os.path.join(self.projectDirPath, self.vsimLogPath)


class RegisterValueComparator( object ):
    def __init__( self, testCodeName ):
        self.testCodeName = testCodeName

    def Compare( self, refRegValueDict, outFileName ):
        # ReadOutFile
        outFile = open( outFileName, 'r' )
        self.outRegTextList = []
        for line in outFile:
            self.outRegTextList.append( line.lstrip().rstrip() )
        outFile.close()

        # PrintDiff
        self.numComparedReg = 0
        self.diffInfoList = []
        for ( regNum, refValue ) in refRegValueDict.items():
            self.numComparedReg += 1
            refText = "0x%0x" % refValue
            outText = self.outRegTextList[ regNum ]

            try:
                outValue = int( outText, 0 )

                # outValueは32bitの16進数なので符号なしで扱うが、
                # refValueは符号ありで与えられることがある。
                # 両者を適切に比較するために補正する
                if (refValue < 0):
                    refValue = (2**32 + refValue)

                refText = "0x%0x" % refValue
                outText = "0x%0x" % outValue

                # refとoutが不一致ならdiffInfoListに追加
                if ( refValue != outValue ):
                    self.diffInfoList.append( (regNum, refText, outText ) )
            except ValueError:
                self.diffInfoList.append( (regNum, refText, outText ) )

        self.isMatched = ( len( self.diffInfoList ) == 0 )


    # 比較結果を表示。Compareを呼んだ後に呼ぶ必要がある
    def PrintCompareResult( self ):
        if ( self.isMatched ):
            print('OK ( %s ) : %d registers have correct values.' % ( self.testCodeName, self.numComparedReg ))
        else:
            print('NG ( %s ) : some registers have incorrect values.' % self.testCodeName)
            for diffInfo in self.diffInfoList:
                print('R%d\t %s (ref)\t-> %s (out)' % ( diffInfo[0], diffInfo[1], diffInfo[2] ))

    # refとoutが一致しているかどうかを返す。Compareを呼んだ後に呼ぶ必要がある
    def IsMatched( self ):
        return self.isMatched

# シリアル出力を検証するため、
# あらかじめ用意したrefファイルと比較する。
class SerialOutputComparator( object ):
    def __init__( self, testCodeName, matchPrefix=False ):
        self.testCodeName = testCodeName
        self.matchPrefix = matchPrefix

    def Compare( self, refFileName, outFileName ):
        # Preserve all output bytes; decoding errors must not hide mismatches.
        # Normalize CRLF and CR to LF, as the previous text-mode reads did.
        with open(outFileName, 'rb') as outFile:
            self.outData = outFile.read().replace(b'\r\n', b'\n').replace(b'\r', b'\n')
        with open(refFileName, 'rb') as refFile:
            self.refData = refFile.read().replace(b'\r\n', b'\n').replace(b'\r', b'\n')

        if self.matchPrefix:
            # Continuous tests must produce the entire, nonempty reference.
            self.isMatched = bool(self.refData) and self.outData.startswith(self.refData)
        else:
            self.isMatched = self.outData == self.refData

    # 比較結果を表示。Compareを呼んだ後に呼ぶ必要がある
    def PrintCompareResult( self ):
        if self.isMatched:
            print("OK ( %s ) : Serial output text is correct." % ( self.testCodeName ))
        else:
            print("NG ( %s ) : Serial output text is incorrect." % ( self.testCodeName ))
            print("Expected %d bytes, got %d (%s match)." %
                  (len(self.refData), len(self.outData), 'prefix' if self.matchPrefix else 'exact'))
            print("--------\nREF\n--------")
            print(self.refData.decode('utf-8', errors='backslashreplace'))
            print("--------\nOUT\n--------")
            print(self.outData.decode('utf-8', errors='backslashreplace'))

    # refとoutが一致しているかどうかを返す。Compareを呼んだ後に呼ぶ必要がある
    def IsMatched( self ):
        return self.isMatched


def PrintBenchmarkScore(benchmark, comparator, expectedIterations=None):
    # The complete reference must precede exactly one measurement report.
    record = comparator.outData[len(comparator.refData):]
    match = re.fullmatch(rb'RSD benchmark: iterations=([0-9]+) cycles=0x([0-9a-fA-F]{8})\n', record)
    if match is not None:
        iterations, cycles = int(match[1]), int(match[2], 16)
        if expectedIterations is not None and iterations != expectedIterations:
            raise ValueError('Benchmark iteration count differs from the build setting')
    elif benchmark == 'dhrystone' and expectedIterations is not None:
        # Accept reports from the earlier mcycle/minstret measurement port.
        # Its report omits the iteration count, so the caller must supply it.
        match = re.fullmatch(rb'RSD measured cycles : ([0-9]+)\nRSD measured instructions : ([0-9]+)\n', record)
        if match is None or not 0 < int(match[2]) <= 0xffffffff:
            raise ValueError('Missing or malformed benchmark measurement')
        iterations, cycles = expectedIterations, int(match[1])
    else:
        raise ValueError('Missing or malformed benchmark measurement')
    if not 0 < iterations <= 0xffffffff or not 0 < cycles <= 0xffffffff:
        raise ValueError('Benchmark iterations and cycles must be positive 32-bit values')
    score = iterations * 1000000 / cycles
    label = 'CoreMark/MHz'
    if benchmark == 'dhrystone':
        score /= 1757
        label = 'Dhrystone DMIPS/MHz'
    print('%s: %.6f (%d iterations, %d cycles; simulation estimate)' %
          (label, score, iterations, cycles))


# テストに失敗して結果が出なかった時に、
# CompareRegValue()で前回のテスト結果が使われるのを防ぐため、
# 前回のテスト結果のファイルを削除する。
def RemoveTestResult( regOutPath, serialOutPath ):
    # OSErrorを無視するためにtry-exceptを使用
    try:
        print("Remove " + regOutPath)
        os.remove( regOutPath )
    except:
        pass
    try:
        os.remove( serialOutPath )
    except:
        pass

#---------------------------
# The entry point of this program
#
# parse option
parser = OptionParser()
parser.add_option('-o', '--omit-questasim-message',
                  action='store_true', dest='omitQuestasimMessage', default=False,
                  help="Omit output messages of QuestaSim.")
parser.add_option('-l', '--rsd-log',
                  action='store', type='string', dest='rsdLogFileName',
                  help="Specify an RSD log file name.")
parser.add_option('-s', '--simulator',
                  action='store', type='string', dest='simulatorName',
                  help="Specify the name of a simulator [questa/modelsim/verilator/vivadosim/post-synthesis/post-synthesis-vcs]. Post-synthesis modes check termination and UART without register dumps. Default: modelsim.")
parser.add_option('-q', '--quiet',
                  action='store_true', dest='quietMode', default=False,
                  help="Omit any messages of this script")
parser.add_option('-e', '--return-error-code',
                  action='store', type='int', dest='returnNonZeroOnError', default=True,
                  help="Return error code on results are not correct")
parser.add_option('--serial-prefix',
                  action='store_true', dest='serialPrefix', default=False,
                  help="When serial.ref.txt exists, require its entire nonempty contents at the start of serial output, allowing additional output (default: exact match).")
parser.add_option('--benchmark', type='choice', choices=['coremark', 'dhrystone'],
                  help="Validate the serial reference and appended cycle measurement, then display a CoreMark/MHz or DMIPS/MHz estimate.")
parser.add_option('--benchmark-iterations', type='int', dest='benchmarkIterations',
                  help="Iteration count used to build a benchmark whose measurement report omits it.")
parser.add_option('--max-test-instructions', type='int', dest='maxTestInstructions',
                  help="Override the configuration's instruction budget for this run.")
options, testCodePathList = parser.parse_args()
if options.benchmarkIterations is not None:
    if not options.benchmark or not 0 < options.benchmarkIterations <= 0xffffffff:
        parser.error('--benchmark-iterations requires --benchmark and a positive 32-bit count')
if options.maxTestInstructions is not None and not 0 < options.maxTestInstructions <= 2**63 - 1:
    parser.error('--max-test-instructions must be a positive 64-bit count')

if not testCodePathList:
    print ("Error : no TestCode specified.")
    sys.exit(3)

# Detect a simulation mode
simName = "modelsim"
if options.simulatorName is not None:
    simName = options.simulatorName
    if simName == "verilator":
        simName = "verilator"
    elif simName == "vivadosim":
        simName = "vivadosim"
    elif simName in ("post-synthesis", "post-synthesis-vcs"):
        pass
    elif simName == "" or simName == "modelsim" or simName == "qeusta":
        simName = "modelsim"
    else:
        print ("Unknown simulation mode: " + simName)
        sys.exit(3)
    

# Main loop
for testCodePath in testCodePathList:
    # 各ファイルのパスを設定
    regOutPath = os.path.join( testCodePath, REG_OUT_FILE_NAME )
    serialOutPath = os.path.join( testCodePath, SERIAL_OUT_FILE_NAME )
    serialRefPath = os.path.join( testCodePath, SERIAL_REF_FILE_NAME )
    if simName in ("post-synthesis", "post-synthesis-vcs") and (
            not os.path.isfile(serialRefPath) or os.path.getsize(serialRefPath) == 0):
        print('NG ( %s ) : Post-synthesis requires a nonempty serial.ref.txt.' % testCodePath,
              file=sys.stderr)
        sys.exit(3)
    if options.benchmark and not os.path.isfile(serialRefPath):
        print('NG ( %s ) : Benchmark requires serial.ref.txt.' % testCodePath, file=sys.stderr)
        sys.exit(3)

    # 過去のテスト結果を消去
    RemoveTestResult( regOutPath, serialOutPath )

    # cfg.xml読み込み
    cfgXmlPath = os.path.join( testCodePath, CFG_XML_FILE_NAME )
    config = ConfigParser()
    try:
        config.Parse( cfgXmlPath )
        if options.maxTestInstructions is not None:
            config.maxTestInstructions = options.maxTestInstructions
    except (TestConfigError, ElementTree.ParseError, OSError, ValueError, KeyError) as error:
        print('NG ( %s ) : Invalid configuration: %s' % (testCodePath, error), file=sys.stderr)
        sys.exit(3)

    # シミュレーション実行
    simDriver = None
    if simName == "modelsim":
        simDriver = SimulationDriver(QUESTASIM_PROJECT_DIR_PATH, testCodePath, config, options)
    elif simName == "post-synthesis":
        simDriver = PostSynthesisSimulationDriver(testCodePath, config, options)
    elif simName == "post-synthesis-vcs":
        simDriver = VCSPostSynthesisSimulationDriver(testCodePath, config, options)
    elif simName == "vivadosim":
        simDriver = VivadoSimulationDriver(VIVADOSIM_PROJECT_DIR_PATH, testCodePath, config, options)
    else:
        simDriver = VerilatorSimulationDriver(VERILATED_FILE_NAME, testCodePath, config, options)
    try:
        simDriver.RunSimulation()
        terminationReason = CheckSimulationResult(config, simDriver.GetLogPath())
    except SimulationError as error:
        print('NG ( %s ) : %s' % (testCodePath, error), file=sys.stderr)
        sys.exit(3)

    # シミュレーション時のレジスタの値を、リファレンスと比較
    # Synthesized netlists do not expose the architectural register dump.
    regValuesMatched = True
    if simName in ("post-synthesis", "post-synthesis-vcs"):
        print('OK ( %s ) : Execution completed (%s).' % (testCodePath, terminationReason))
    else:
        regValueComparator = RegisterValueComparator( testCodePath )
        regValueComparator.Compare( config.registerValueDict, regOutPath )
        regValuesMatched = regValueComparator.IsMatched()
        if config.registerValueDict:
            regValueComparator.PrintCompareResult()
        else:
            print('OK ( %s ) : Execution completed (%s).' % (testCodePath, terminationReason))

    # シミュレーション時のシリアル出力を、リファレンスと比較
    if os.path.exists( serialRefPath ):
        # シリアル出力比較は、refファイルがある場合のみやる
        serialOutComparator = SerialOutputComparator(
            testCodePath, matchPrefix=options.serialPrefix or bool(options.benchmark))
        serialOutComparator.Compare( serialRefPath, serialOutPath )
        serialOutComparator.PrintCompareResult()

    if options.benchmark and regValuesMatched and serialOutComparator.IsMatched():
        try:
            PrintBenchmarkScore(options.benchmark, serialOutComparator, options.benchmarkIterations)
        except ValueError as error:
            print('NG ( %s ) : %s' % (testCodePath, error), file=sys.stderr)
            sys.exit(3)

    # テスト結果が違っていたら、エラーを返す
    if not options.returnNonZeroOnError:
        sys.exit(0)
    else:
        if os.path.exists( serialRefPath ):
            if not regValuesMatched:
                sys.exit(2)
            if not serialOutComparator.IsMatched():
                sys.exit(1)
        else:
            if not regValuesMatched:
                sys.exit(2)
