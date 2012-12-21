-- 
-- Created by SQL::Translator::Producer::MySQL
-- Created on Tue May 22 14:28:20 2012
-- 
SET foreign_key_checks=0;
--
-- Table: `gene`
--
CREATE TABLE `gene` (
  `id` integer unsigned NOT NULL,
  `symbol` varchar(100) NOT NULL,
  `status` varchar(30),
  `synonyms` varchar(4000),
  `description` varchar(4000),
  INDEX `gene_idx_symbol` (`symbol`),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;
--
-- Table: `organism`
--
CREATE TABLE `organism` (
  `id` integer unsigned NOT NULL auto_increment,
  `tax_id` varchar(100) NOT NULL,
  `name` varchar(100),
  PRIMARY KEY (`id`),
  UNIQUE `organism_un_name` (`name`),
  UNIQUE `organism_un_tax_id` (`tax_id`)
) ENGINE=InnoDB;
--
-- Table: `contrast_data_set`
--
CREATE TABLE `contrast_data_set` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(200) NOT NULL,
  `source_data_file_id_type` varchar(100) NOT NULL,
  `source_data_file_name` varchar(1000) NOT NULL,
  `collapsing_method` varchar(100) NOT NULL,
  `creation_time` timestamp NOT NULL DEFAULT now(),
  `description` text,
  `data_processing_report` text,
  `organism_id` integer unsigned NOT NULL,
  INDEX `contrast_data_set_idx_organism_id` (`organism_id`),
  INDEX `contrast_data_set_idx_source_data_file_id_type` (`source_data_file_id_type`),
  PRIMARY KEY (`id`),
  UNIQUE `contrast_data_set_un_name` (`name`),
  CONSTRAINT `contrast_data_set_fk_organism_id` FOREIGN KEY (`organism_id`) REFERENCES `organism` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
-- Table: `gene_set`
--
CREATE TABLE `gene_set` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(200) NOT NULL,
  `source_data_file_id_type` varchar(100) NOT NULL,
  `source_data_file_name` varchar(1000) NOT NULL,
  `creation_time` timestamp NOT NULL DEFAULT now(),
  `contrast_name` varchar(200),
  `type` varchar(10),
  `description` text,
  `data_processing_report` text,
  `organism_id` integer unsigned NOT NULL,
  INDEX `gene_set_idx_organism_id` (`organism_id`),
  INDEX `gene_set_idx_source_data_file_id_type` (`source_data_file_id_type`),
  PRIMARY KEY (`id`),
  UNIQUE `gene_set_un_name_contrast_name_type` (`name`, `contrast_name`, `type`),
  CONSTRAINT `gene_set_fk_organism_id` FOREIGN KEY (`organism_id`) REFERENCES `organism` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
-- Table: `contrast`
--
CREATE TABLE `contrast` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(200) NOT NULL,
  `contrast_data_set_id` integer unsigned NOT NULL,
  INDEX `contrast_idx_contrast_data_set_id` (`contrast_data_set_id`),
  PRIMARY KEY (`id`),
  UNIQUE `contrast_un_contrast_data_set_contrast_name` (`contrast_data_set_id`, `name`),
  CONSTRAINT `contrast_fk_contrast_data_set_id` FOREIGN KEY (`contrast_data_set_id`) REFERENCES `contrast_data_set` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
-- Table: `contrast_data_set_annotation`
--
CREATE TABLE `contrast_data_set_annotation` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(100) NOT NULL,
  `value` varchar(4000) NOT NULL,
  `contrast_data_set_id` integer unsigned NOT NULL,
  INDEX `contrast_data_set_annotation_idx_contrast_data_set_id` (`contrast_data_set_id`),
  PRIMARY KEY (`id`),
  CONSTRAINT `contrast_data_set_annotation_fk_contrast_data_set_id` FOREIGN KEY (`contrast_data_set_id`) REFERENCES `contrast_data_set` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
-- Table: `contrast_data_set_source_data_file`
--
CREATE TABLE `contrast_data_set_source_data_file` (
  `contrast_data_set_id` integer unsigned NOT NULL,
  `data` longtext NOT NULL,
  INDEX (`contrast_data_set_id`),
  PRIMARY KEY (`contrast_data_set_id`),
  CONSTRAINT `contrast_data_set_source_data_file_fk_contrast_data_set_id` FOREIGN KEY (`contrast_data_set_id`) REFERENCES `contrast_data_set` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;
--
-- Table: `gene_set_annotation`
--
CREATE TABLE `gene_set_annotation` (
  `id` integer unsigned NOT NULL auto_increment,
  `name` varchar(100) NOT NULL,
  `value` varchar(4000) NOT NULL,
  `gene_set_id` integer unsigned NOT NULL,
  INDEX `gene_set_annotation_idx_gene_set_id` (`gene_set_id`),
  PRIMARY KEY (`id`),
  CONSTRAINT `gene_set_annotation_fk_gene_set_id` FOREIGN KEY (`gene_set_id`) REFERENCES `gene_set` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
-- Table: `gene_set_source_data_file`
--
CREATE TABLE `gene_set_source_data_file` (
  `gene_set_id` integer unsigned NOT NULL,
  `data` longtext NOT NULL,
  INDEX (`gene_set_id`),
  PRIMARY KEY (`gene_set_id`),
  CONSTRAINT `gene_set_source_data_file_fk_gene_set_id` FOREIGN KEY (`gene_set_id`) REFERENCES `gene_set` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;
--
-- Table: `contrast_data_file`
--
CREATE TABLE `contrast_data_file` (
  `contrast_id` integer unsigned NOT NULL,
  `data` longtext NOT NULL,
  INDEX (`contrast_id`),
  PRIMARY KEY (`contrast_id`),
  CONSTRAINT `contrast_data_file_fk_contrast_id` FOREIGN KEY (`contrast_id`) REFERENCES `contrast` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;
--
-- Table: `contrast_gene_set`
--
CREATE TABLE `contrast_gene_set` (
  `id` integer unsigned NOT NULL auto_increment,
  `type` varchar(10) NOT NULL,
  `contrast_id` integer unsigned NOT NULL,
  INDEX `contrast_gene_set_idx_contrast_id` (`contrast_id`),
  PRIMARY KEY (`id`),
  UNIQUE `contrast_gene_set_un_contrast_gene_set_type` (`contrast_id`, `type`),
  CONSTRAINT `contrast_gene_set_fk_contrast_id` FOREIGN KEY (`contrast_id`) REFERENCES `contrast` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
-- Table: `gene_set_gene`
--
CREATE TABLE `gene_set_gene` (
  `gene_set_id` integer unsigned NOT NULL,
  `gene_id` integer unsigned NOT NULL,
  `rank` integer unsigned,
  INDEX `gene_set_gene_idx_gene_id` (`gene_id`),
  INDEX `gene_set_gene_idx_gene_set_id` (`gene_set_id`),
  PRIMARY KEY (`gene_set_id`, `gene_id`),
  UNIQUE `gene_set_gene_un_gene_set_rank` (`gene_set_id`, `rank`),
  CONSTRAINT `gene_set_gene_fk_gene_id` FOREIGN KEY (`gene_id`) REFERENCES `gene` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `gene_set_gene_fk_gene_set_id` FOREIGN KEY (`gene_set_id`) REFERENCES `gene_set` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
-- Table: `contrast_gene_set_gene`
--
CREATE TABLE `contrast_gene_set_gene` (
  `contrast_gene_set_id` integer unsigned NOT NULL,
  `gene_id` integer unsigned NOT NULL,
  `rank` integer unsigned NOT NULL,
  INDEX `contrast_gene_set_gene_idx_contrast_gene_set_id` (`contrast_gene_set_id`),
  INDEX `contrast_gene_set_gene_idx_gene_id` (`gene_id`),
  PRIMARY KEY (`contrast_gene_set_id`, `gene_id`),
  UNIQUE `contrast_gene_set_gene_un_gene_set_rank` (`contrast_gene_set_id`, `rank`),
  CONSTRAINT `contrast_gene_set_gene_fk_contrast_gene_set_id` FOREIGN KEY (`contrast_gene_set_id`) REFERENCES `contrast_gene_set` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `contrast_gene_set_gene_fk_gene_id` FOREIGN KEY (`gene_id`) REFERENCES `gene` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
--
--
SET foreign_key_checks=1;
--
--

