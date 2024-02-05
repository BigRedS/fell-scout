create database if not exists fellscout;
use fellscout;
-- MariaDB dump 10.19  Distrib 10.11.4-MariaDB, for debian-linux-gnu (aarch64)
--
-- Host: localhost    Database: fellscout-dev
-- ------------------------------------------------------
-- Server version	10.11.4-MariaDB-1~deb12u1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `checkpoints_teams`
--

DROP TABLE IF EXISTS `checkpoints_teams`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `checkpoints_teams` (
  `checkpoint` tinyint(4) NOT NULL,
  `team_number` smallint(6) NOT NULL,
  `time` datetime DEFAULT NULL,
  `previous_checkpoint` tinyint(4) DEFAULT NULL,
  `seconds_since_previous_checkpoint` int(11) DEFAULT NULL,
  PRIMARY KEY (`checkpoint`,`team_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `checkpoints_teams_predictions`
--

DROP TABLE IF EXISTS `checkpoints_teams_predictions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `checkpoints_teams_predictions` (
  `checkpoint` tinyint(4) NOT NULL,
  `team_number` smallint(6) NOT NULL,
  `expected_time` datetime DEFAULT NULL,
  PRIMARY KEY (`checkpoint`,`team_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `config`
--

DROP TABLE IF EXISTS `config`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `config` (
  `name` varchar(100) DEFAULT NULL,
  `value` varchar(100) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  UNIQUE KEY `name_2` (`name`),
  KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `entrants`
--

DROP TABLE IF EXISTS `entrants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `entrants` (
  `team` smallint(6) DEFAULT NULL,
  `entrant_name` text DEFAULT NULL,
  `district` text DEFAULT NULL,
  `unit` text DEFAULT NULL,
  `completed` tinyint(1) DEFAULT NULL,
  `retired` tinyint(1) DEFAULT NULL,
  `code` char(4) NOT NULL,
  `last_checkpoint_time` datetime DEFAULT NULL,
  `last_checkpoint` tinyint(4) DEFAULT NULL,
  PRIMARY KEY (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `legs`
--

DROP TABLE IF EXISTS `legs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `legs` (
  `from` tinyint(4) NOT NULL,
  `to` tinyint(4) NOT NULL,
  `seconds` int(11) DEFAULT NULL,
  `leg_name` tinytext DEFAULT NULL,
  PRIMARY KEY (`from`,`to`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `logs`
--

DROP TABLE IF EXISTS `logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `logs` (
  `name` text DEFAULT NULL,
  `message` text DEFAULT NULL,
  `time` datetime DEFAULT current_timestamp(),
  UNIQUE KEY `name_2` (`name`) USING HASH,
  KEY `name` (`name`(768))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `routes`
--

DROP TABLE IF EXISTS `routes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `routes` (
  `route_name` varchar(32) NOT NULL,
  `index` tinyint(4) NOT NULL,
  `leg_name` tinytext DEFAULT NULL,
  PRIMARY KEY (`index`,`route_name`),
  KEY `route_name` (`route_name`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `routes_checkpoints`
--

DROP TABLE IF EXISTS `routes_checkpoints`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `routes_checkpoints` (
  `route_name` text DEFAULT NULL,
  `checkpoint_number` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `scratch_team_entrants`
--

DROP TABLE IF EXISTS `scratch_team_entrants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `scratch_team_entrants` (
  `team_number` smallint(6) NOT NULL,
  `entrant_code` char(4) NOT NULL,
  `previous_team_number` smallint(6) DEFAULT NULL,
  PRIMARY KEY (`team_number`,`entrant_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `scratch_teams`
--

DROP TABLE IF EXISTS `scratch_teams`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `scratch_teams` (
  `team_number` smallint(6) NOT NULL AUTO_INCREMENT,
  `team_name` text DEFAULT NULL,
  PRIMARY KEY (`team_number`),
  UNIQUE KEY `team_name` (`team_name`) USING HASH
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `teams`
--

DROP TABLE IF EXISTS `teams`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `teams` (
  `team_number` smallint(6) NOT NULL,
  `team_name` text DEFAULT NULL,
  `unit` text DEFAULT NULL,
  `district` text DEFAULT NULL,
  `representative_entrant` tinytext DEFAULT NULL,
  `route` tinytext DEFAULT NULL,
  `last_checkpoint` tinyint(4) DEFAULT NULL,
  `last_checkpoint_time` datetime DEFAULT NULL,
  `next_checkpoint` tinyint(4) DEFAULT NULL,
  `current_leg` tinytext DEFAULT NULL,
  `current_leg_index` smallint(6) DEFAULT NULL,
  `completed` tinyint(4) DEFAULT NULL,
  PRIMARY KEY (`team_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2024-02-05 22:36:52
-- MariaDB dump 10.19  Distrib 10.11.4-MariaDB, for debian-linux-gnu (aarch64)
--
-- Host: localhost    Database: fellscout-dev
-- ------------------------------------------------------
-- Server version	10.11.4-MariaDB-1~deb12u1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `config`
--

DROP TABLE IF EXISTS `config`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `config` (
  `name` varchar(100) DEFAULT NULL,
  `value` varchar(100) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  UNIQUE KEY `name_2` (`name`),
  KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `config`
--

LOCK TABLES `config` WRITE;
/*!40000 ALTER TABLE `config` DISABLE KEYS */;
INSERT INTO `config` VALUES
('route_50mile','1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19','space-separated list of checkpoints on 50 mile route'),
('route_50km','3 4 5 6 7 8 13 14 15 16 17 18 19','space-separated list of checkpoints on 50km route'),
('route_30km','3 4 5 14 15 16 17 18 19','space-separated list of checkpoints on 30km route'),
('percentile','80','When calculating expected times for legs, we use this percentile. Normally 90'),
('felltrack_owner','chiltern2',NULL),
('felltrack_username','someguy',NULL),
('felltrack_password','supersecret',NULL),
('ignore_teams','','A space-separated list of teams to ignore'),
('ignore_future_events','on','Skip any events that appear to have happened in the future. Should only be useful when testing with old data'),
('skip_fetch_from_felltrack','on','Set to \'on\' to not download fresh data from felltrack; will continue to use the last-downloaded CSV file'),
('lateness_percent_amber','30','When a team is on the laterunners page, if thir percent-lateness is higher than this and lower than lateness_percent_red, they will be highlighted in yellow. Normally 30'),
('lateness_percent_red','80','When a team is on the laterunners page, if their percent-lateness is higher than this they will be highlighted in red. Normally 80'),
('percentile_sample_size','60','When calculating the expected times for legs we want to favour the more-recent teams; this sets the size of the most-recent percentile of the sample set that we go on to take the time-taken percentile of. Normally 60'),
('percentile_min_sample','10','When calculating a percentile, after applying any percentile_sample_size, if the number of samples is less than this a simple mean will be taken instead. Normally 10');
/*!40000 ALTER TABLE `config` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2024-02-05 22:36:52
